import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../theme/theme.dart';
import 'confirm_box.dart';
import 'input_dialogs.dart';
import 'media_viewer.dart';
import 'telegram_toast.dart';

const double _boxWideWidth = 364;
const double _boxTitleHeight = 48;

enum _SortMode { online, alphabetical }

Future<void> showContactsBox(BuildContext context) {
  final appState = context.read<AppState>();
  final chatState = context.read<ChatState>();
  final engine = context.read<EngineService>();

  return showDialog<void>(
    context: context,
    builder: (ctx) => ChangeNotifierProvider.value(
      value: appState,
      child: ChangeNotifierProvider.value(
        value: chatState,
        child: Provider<EngineService>.value(
          value: engine,
          child: const _ContactsBox(),
        ),
      ),
    ),
  );
}

class _ContactsBox extends StatefulWidget {
  const _ContactsBox();

  @override
  State<_ContactsBox> createState() => _ContactsBoxState();
}

class _ContactsBoxState extends State<_ContactsBox> {
  List<ContactInfo>? _contacts;
  String _error = '';
  bool _loading = true;
  final _searchController = TextEditingController();
  late final FocusNode _searchFocusNode;
  String _searchQuery = '';
  _SortMode _sortMode = _SortMode.online;
  Timer? _globalSearchTimer;
  bool _globalSearching = false;
  List<ContactInfo>? _globalResults;

  static const _autoSearchTimeout = Duration(milliseconds: 800);
  static const _sortByOnlineThrottle = Duration(milliseconds: 3000);
  Timer? _sortThrottleTimer;
  List<ContactInfo>? _sortedCache;
  StreamSubscription<UserStatusEvent>? _userStatusSub;

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode();
    _loadContacts();
    _searchController.addListener(_onSearchChanged);
    final engine = context.read<EngineService>();
    _userStatusSub = engine.onUserStatus.listen(_onUserStatusChanged);
  }

  @override
  void dispose() {
    _userStatusSub?.cancel();
    _globalSearchTimer?.cancel();
    _sortThrottleTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      _searchQuery = query;
      _globalResults = null;
      _sortedCache = null;
    });
    _globalSearchTimer?.cancel();
    if (query.isNotEmpty) {
      final localCount = _localFiltered(query).length;
      if (localCount < 5) {
        _globalSearchTimer = Timer(_autoSearchTimeout, () => _runGlobalSearch(query));
      }
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _globalSearchTimer?.cancel();
    setState(() {
      _searchQuery = '';
      _globalResults = null;
      _globalSearching = false;
      _sortedCache = null;
    });
  }

  Future<void> _runGlobalSearch(String query) async {
    if (!mounted || query.isEmpty) return;
    setState(() => _globalSearching = true);
    try {
      final appState = context.read<AppState>();
      final engine = context.read<EngineService>();
      final account = appState.activeAccount;
      if (account == null) return;
      if (query.startsWith('@') && query.length > 1) {
        final username = query.substring(1);
        final result = await engine.resolveUsername(account.id, username);
        if (mounted && _searchQuery == query && result != null && result.isNotEmpty) {
          final existing = _contacts ?? [];
          final alreadyHas = existing.any((c) => c.userId == result);
          if (!alreadyHas) {
            try {
              final fullInfo = await engine.getContactFullInfo(account.id, result);
              if (mounted && _searchQuery == query) {
                setState(() {
                  _globalResults = [
                    ContactInfo(
                      userId: result,
                      username: username,
                      displayName: fullInfo['display_name'] as String? ?? '@$username',
                      phone: fullInfo['phone'] as String? ?? '',
                      isBot: fullInfo['is_bot'] as bool? ?? false,
                      isContact: fullInfo['is_contact'] as bool? ?? false,
                      isOnline: fullInfo['is_online'] as bool? ?? false,
                      isVerified: fullInfo['is_verified'] as bool? ?? false,
                      isPremium: fullInfo['is_premium'] as bool? ?? false,
                      avatarB64: fullInfo['avatar_b64'] as String? ?? '',
                      lastSeenKind: fullInfo['last_seen_kind'] as String? ?? '',
                    ),
                  ];
                  _sortedCache = null;
                });
              }
            } catch (_) {
              if (mounted && _searchQuery == query) {
                setState(() {
                  _globalResults = [
                    ContactInfo(userId: result, username: username, displayName: '@$username'),
                  ];
                  _sortedCache = null;
                });
              }
            }
          }
        }
      } else {
        final chats = await engine.searchGlobalChats(account.id, query, limit: 10);
        if (mounted && _searchQuery == query && chats.isNotEmpty) {
          final existing = _contacts ?? [];
          final results = <ContactInfo>[];
          for (final chat in chats) {
            if (chat.type == ChatType.dm && !existing.any((c) => c.userId == chat.chatId)) {
              results.add(ContactInfo(
                userId: chat.chatId,
                displayName: chat.title,
                isBot: chat.isBot,
                isContact: chat.isContact,
                isVerified: chat.isVerified,
                isScam: chat.isScam,
                isFake: chat.isFake,
              ));
            }
          }
          if (results.isNotEmpty) {
            setState(() {
              _globalResults = results;
              _sortedCache = null;
            });
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _globalSearching = false);
  }

  Future<void> _loadContacts() async {
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final account = appState.activeAccount;
    if (account == null) {
      setState(() {
        _error = 'No active account';
        _loading = false;
      });
      return;
    }
    try {
      final contacts = await engine.getContacts(account.id);
      if (mounted) {
        setState(() {
          _contacts = contacts;
          _loading = false;
          _sortedCache = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  static List<String> _nameWords(String name) {
    return name.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  }

  static String _nameFirstLetters(String name) {
    final words = _nameWords(name);
    return words.map((w) => w[0]).join();
  }

  static bool _matchesContact(ContactInfo c, String query) {
    final queryLower = query.toLowerCase();
    final words = _nameWords(c.displayName);
    for (final w in words) {
      if (w.startsWith(queryLower)) return true;
    }
    final firstLetters = _nameFirstLetters(c.displayName);
    if (firstLetters.startsWith(queryLower)) return true;
    final queryParts = queryLower.split(RegExp(r'\s+'));
    if (queryParts.length > 1) {
      var allMatch = true;
      for (final qp in queryParts) {
        if (!words.any((w) => w.startsWith(qp))) {
          allMatch = false;
          break;
        }
      }
      if (allMatch) return true;
    }
    if (c.username.toLowerCase().startsWith(queryLower)) return true;
    if (c.phone.contains(queryLower)) return true;
    if (c.displayName.toLowerCase().contains(queryLower)) return true;
    return false;
  }

  List<ContactInfo> _localFiltered(String query) {
    final all = _contacts ?? [];
    if (query.isEmpty) return all;
    return all.where((c) => _matchesContact(c, query)).toList();
  }

  int _onlineSortKey(ContactInfo c) {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (c.isOnline) return nowSec + 1;
    if (c.lastSeenTs > 0) {
      final onlineTill = c.lastSeenTs;
      final clamped = onlineTill < nowSec + 1 ? onlineTill : nowSec + 1;
      return clamped + 1;
    }
    return 0;
  }

  List<ContactInfo> _sortedContacts(List<ContactInfo> list) {
    final sorted = List<ContactInfo>.from(list);
    switch (_sortMode) {
      case _SortMode.online:
        sorted.sort((a, b) {
          final ka = _onlineSortKey(a);
          final kb = _onlineSortKey(b);
          if (ka != kb) return kb.compareTo(ka);
          return a.label.toLowerCase().compareTo(b.label.toLowerCase());
        });
      case _SortMode.alphabetical:
        sorted.sort(
            (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    }
    return sorted;
  }

  void _throttledRefresh() {
    if (_sortThrottleTimer?.isActive == true) return;
    _sortThrottleTimer = Timer(_sortByOnlineThrottle, () {
      if (mounted) setState(() { _sortedCache = null; });
    });
  }

  void _onUserStatusChanged(UserStatusEvent event) {
    if (!mounted) return;
    final contacts = _contacts;
    if (contacts == null) return;
    final idx = contacts.indexWhere((c) => c.userId == event.userId);
    if (idx >= 0) {
      final c = contacts[idx];
      contacts[idx] = ContactInfo(
        userId: c.userId,
        username: c.username,
        displayName: c.displayName,
        phone: c.phone,
        avatarB64: c.avatarB64,
        isBot: c.isBot,
        isOnline: event.isOnline,
        isContact: c.isContact,
        isMutualContact: c.isMutualContact,
        hasPersonalPhoto: c.hasPersonalPhoto,
        storyCount: c.storyCount,
        hasUnreadStory: c.hasUnreadStory,
        isVerified: c.isVerified,
        isPremium: c.isPremium,
        isScam: c.isScam,
        isFake: c.isFake,
        lastSeenKind: event.lastSeenKind.isNotEmpty ? event.lastSeenKind : c.lastSeenKind,
        lastSeenTs: event.lastSeenMs > 0 ? event.lastSeenMs ~/ 1000 : c.lastSeenTs,
      );
      _sortedCache = null;
    }
    _throttledRefresh();
  }

  List<ContactInfo> get _filteredContacts {
    if (_sortedCache != null) return _sortedCache!;
    final local = _localFiltered(_searchQuery);
    final sorted = _sortedContacts(local);
    if (_globalResults != null && _globalResults!.isNotEmpty) {
      final localIds = sorted.map((c) => c.userId).toSet();
      final extra = _globalResults!.where((c) => !localIds.contains(c.userId));
      _sortedCache = [...sorted, ...extra];
    } else {
      _sortedCache = sorted;
    }
    return _sortedCache!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor =
        isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final hoverBg =
        isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);
    final searchBg =
        isDark ? const Color(0xFF242F3D) : const Color(0xFFF1F1F1);
    final searchFg =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final searchHintFg =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final dividerColor =
        isDark ? const Color(0xFF101921) : const Color(0xFFE8E8E8);
    final buttonColor =
        isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);

    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return PopScope(
      canPop: _searchQuery.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _searchQuery.isNotEmpty) {
          _clearSearch();
        }
      },
      child: Dialog(
        backgroundColor: bgColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: _boxWideWidth,
          maxHeight: maxHeight,
          minWidth: _boxWideWidth,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title bar: 48px, "Contacts" left, sort toggle right.
            SizedBox(
              height: _boxTitleHeight,
              child: Row(
                children: [
                  const SizedBox(width: 24),
                  Expanded(
                    child: Text(
                      'Contacts',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                  _SortToggle(
                    mode: _sortMode,
                    isDark: isDark,
                    onToggle: () {
                      setState(() {
                        _sortMode = _sortMode == _SortMode.online
                            ? _SortMode.alphabetical
                            : _SortMode.online;
                        _sortedCache = null;
                      });
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  autofocus: true,
                  style: TextStyle(fontSize: 13, color: searchFg),
                  decoration: InputDecoration(
                    hintText: 'Search',
                    hintStyle: TextStyle(fontSize: 13, color: searchHintFg),
                    prefixIcon:
                        Icon(Icons.search, size: 18, color: searchHintFg),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            onPressed: _clearSearch,
                            icon: Icon(Icons.close, size: 16, color: searchHintFg),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            splashRadius: 14,
                          )
                        : null,
                    filled: true,
                    fillColor: searchBg,
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 0, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: dividerColor),
            Flexible(
              child: _loading
                  ? SizedBox(
                      height: 200,
                      child: Center(
                        child: Text(
                          'Loading...',
                          style: TextStyle(fontSize: 13, color: subtextColor),
                        ),
                      ),
                    )
                  : _error.isNotEmpty
                      ? SizedBox(
                          height: 200,
                          child: Center(
                            child: Text(
                              _error,
                              style: TextStyle(
                                  color: subtextColor, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : _filteredContacts.isEmpty && !_globalSearching
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 10),
                              child: SizedBox(
                                height: 200,
                                child: Center(
                                  child: Text(
                                    _searchQuery.isNotEmpty
                                        ? 'No contacts found'
                                        : 'No contacts yet',
                                    style: TextStyle(
                                        color: subtextColor, fontSize: 13),
                                  ),
                                ),
                              ),
                            )
                          : Column(
                              children: [
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: _filteredContacts.length,
                                    itemBuilder: (context, index) {
                                      final contact = _filteredContacts[index];
                                      return _ContactRow(
                                        contact: contact,
                                        textColor: textColor,
                                        subtextColor: subtextColor,
                                        hoverBg: hoverBg,
                                        bgColor: bgColor,
                                        isDark: isDark,
                                        onTap: () => _openChat(contact),
                                        onMiddleClick: () => _openChatInBackground(contact),
                                        onStoryTap: contact.hasStories
                                            ? () => _openStory(contact)
                                            : null,
                                        onContactChanged: _loadContacts,
                                      );
                                    },
                                  ),
                                ),
                                if (_globalSearching)
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: subtextColor,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Searching...',
                                          style: TextStyle(
                                              color: subtextColor,
                                              fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
            ),
            // Bottom button bar: "Add Contact" left, "Close" right.
            Divider(height: 1, color: dividerColor),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => _showAddContactBox(context),
                    style: TextButton.styleFrom(
                      foregroundColor: buttonColor,
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    child: const Text('Add Contact'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: buttonColor,
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    child: const Text('Close'),
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

  void _showAddContactBox(BuildContext context) {
    showAddContactBox(context).then((added) {
      if (added == true && mounted) {
        _loadContacts();
      }
    });
  }

  void _openChat(ContactInfo contact) {
    _navigateToChat(contact);
    Navigator.of(context).pop();
  }

  void _openChatInBackground(ContactInfo contact) {
    final accountId = context.read<AppState>().activeAccountId;
    if (accountId == null || accountId.isEmpty) return;
    _navigateToChat(contact);
    if (mounted) showTelegramToast(context, 'Opened chat with ${contact.label}');
  }

  void _navigateToChat(ContactInfo contact) {
    final chatState = context.read<ChatState>();
    final chats = chatState.chats;
    ChatInfo? dm;
    for (final c in chats) {
      if (c.type == ChatType.dm && c.chatId == contact.userId) {
        dm = c;
        break;
      }
    }
    if (dm != null) {
      chatState.openChat(dm);
    } else {
      final syntheticDm = ChatInfo(
        accountId: context.read<AppState>().activeAccountId ?? '',
        chatId: contact.userId,
        title: contact.displayName.isNotEmpty ? contact.displayName : contact.username,
        type: ChatType.dm,
      );
      chatState.openChat(syntheticDm);
    }
  }

  void _openStory(ContactInfo contact) async {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId == null || accountId.isEmpty) return;
    try {
      final stories = await engine.fetchPeerStories(accountId, contact.userId);
      if (stories.isEmpty || !mounted) return;
      final selfId = appState.activeAccount?.selfUserId ?? '';
      Navigator.of(context).pop();
      StoriesViewer.open(
        context,
        stories: stories,
        peerName: contact.displayName.isNotEmpty
            ? contact.displayName
            : contact.username,
        isOwnStory: selfId.isNotEmpty && contact.userId == selfId,
        peerId: contact.userId,
      );
    } catch (e) {
      debugPrint('Failed to load stories: $e');
    }
  }
}

class _SortToggle extends StatefulWidget {
  final _SortMode mode;
  final bool isDark;
  final VoidCallback onToggle;

  const _SortToggle({
    required this.mode,
    required this.isDark,
    required this.onToggle,
  });

  @override
  State<_SortToggle> createState() => _SortToggleState();
}

class _SortToggleState extends State<_SortToggle> with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late final AnimationController _highlightAnim;

  @override
  void initState() {
    super.initState();
    _highlightAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    _highlightAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);
    final hoverColor = widget.isDark
        ? const Color(0xFF202B36)
        : const Color(0xFFF1F1F1);

    return AnimatedBuilder(
      animation: _highlightAnim,
      builder: (context, child) {
        final highlightOpacity = _highlightAnim.status == AnimationStatus.completed
            ? 0.0
            : (1.0 - _highlightAnim.value) * 0.3;
        return MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onToggle,
            child: SizedBox(
              width: 48,
              height: 54,
              child: Stack(
                children: [
                  Positioned(
                    left: 1,
                    top: 6,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _hovered
                            ? hoverColor
                            : highlightOpacity > 0
                                ? hoverColor.withOpacity(highlightOpacity)
                                : Colors.transparent,
                      ),
                      alignment: Alignment.center,
                      child: CustomPaint(
                        size: const Size(22, 22),
                        painter: widget.mode == _SortMode.online
                            ? _ContactsSortAlphabetPainter(color: iconColor)
                            : _ContactsSortOnlinePainter(color: iconColor),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ContactsSortAlphabetPainter extends CustomPainter {
  final Color color;
  _ContactsSortAlphabetPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final y1 = size.height * 0.27;
    final y2 = size.height * 0.50;
    final y3 = size.height * 0.73;
    final x0 = size.width * 0.05;
    canvas.drawLine(Offset(x0, y1), Offset(x0 + size.width * 0.50, y1), paint);
    canvas.drawLine(Offset(x0, y2), Offset(x0 + size.width * 0.38, y2), paint);
    canvas.drawLine(Offset(x0, y3), Offset(x0 + size.width * 0.26, y3), paint);
    final tp = TextPainter(
      text: TextSpan(
        text: 'A',
        style: TextStyle(
          fontSize: size.height * 0.52,
          fontWeight: FontWeight.w700,
          color: color,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width * 0.68, size.height * 0.22));
  }

  @override
  bool shouldRepaint(_ContactsSortAlphabetPainter old) => old.color != color;
}

class _ContactsSortOnlinePainter extends CustomPainter {
  final Color color;
  _ContactsSortOnlinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final y1 = size.height * 0.27;
    final y2 = size.height * 0.50;
    final y3 = size.height * 0.73;
    final x0 = size.width * 0.05;
    canvas.drawLine(Offset(x0, y1), Offset(x0 + size.width * 0.50, y1), paint);
    canvas.drawLine(Offset(x0, y2), Offset(x0 + size.width * 0.38, y2), paint);
    canvas.drawLine(Offset(x0, y3), Offset(x0 + size.width * 0.26, y3), paint);
    final cx = size.width * 0.78;
    final cy = size.height * 0.50;
    final r = size.width * 0.17;
    final circlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawCircle(Offset(cx, cy), r, circlePaint);
    final handPaint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, cy), Offset(cx, cy - r * 0.65), handPaint);
    canvas.drawLine(Offset(cx, cy), Offset(cx + r * 0.55, cy), handPaint);
  }

  @override
  bool shouldRepaint(_ContactsSortOnlinePainter old) => old.color != color;
}

class _ContactRow extends StatefulWidget {
  final ContactInfo contact;
  final Color textColor;
  final Color subtextColor;
  final Color hoverBg;
  final Color bgColor;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onMiddleClick;
  final VoidCallback? onStoryTap;
  final VoidCallback? onContactChanged;

  const _ContactRow({
    required this.contact,
    required this.textColor,
    required this.subtextColor,
    required this.hoverBg,
    required this.bgColor,
    required this.isDark,
    required this.onTap,
    this.onMiddleClick,
    this.onStoryTap,
    this.onContactChanged,
  });

  @override
  State<_ContactRow> createState() => _ContactRowState();
}

class _ContactRowState extends State<_ContactRow> {
  bool _hovered = false;
  Uint8List? _avatarBytes;

  @override
  void initState() {
    super.initState();
    _decodeAvatar();
  }

  @override
  void didUpdateWidget(covariant _ContactRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contact.avatarB64 != widget.contact.avatarB64) {
      _decodeAvatar();
    }
  }

  void _decodeAvatar() {
    final b64 = widget.contact.avatarB64;
    _avatarBytes = b64.isNotEmpty ? base64Decode(b64) : null;
  }

  static const _rowHeight = 56.0;
  static const _rowHeightStory = 52.0;
  static const _avatarSize = 42.0;
  static const _avatarLeft = 16.0;
  static const _avatarTop = 7.0;
  static const _avatarLeftStory = 18.0;
  static const _avatarTopStory = 5.0;
  static const _nameLeft = 74.0;
  static const _nameTop = 9.0;
  static const _nameLeftStory = 70.0;
  static const _nameTopStory = 7.0;
  static const _statusLeft = 74.0;
  static const _statusTop = 30.0;
  static const _statusLeftStory = 70.0;
  static const _statusTopStory = 27.0;
  static const _rightPad = 16.0;
  static const _ringStrokeUnread = 2.0;
  static const _ringStrokeRead = 1.0;
  static const _ringGap = 2.0;

  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];

  static const _onlineColor = Color(0xFF4dc920);
  static const _statusOnlineColor = Color(0xFF4fae4e);
  static const _statusOfflineDay = Color(0xFF999999);
  static const _statusOfflineNight = Color(0xFF6C7883);
  static const _statusHoverDay = Color(0xFF7c99b2);
  static const _statusHoverNight = Color(0xFF7c99b2);

  String _statusText(ContactInfo c) {
    if (c.isOnline || c.lastSeenKind == 'online') return 'online';
    switch (c.lastSeenKind) {
      case 'recently':
        return 'last seen recently';
      case 'within_week':
        return 'last seen within a week';
      case 'within_month':
        return 'last seen within a month';
      case 'long_ago':
        return 'last seen a long time ago';
      case 'exact':
        if (c.lastSeenTs > 0) {
          final dt = DateTime.fromMillisecondsSinceEpoch(c.lastSeenTs * 1000);
          final now = DateTime.now();
          final diff = now.difference(dt);
          if (diff.inDays == 0) {
            final h = dt.hour.toString().padLeft(2, '0');
            final m = dt.minute.toString().padLeft(2, '0');
            return 'last seen today at $h:$m';
          } else if (diff.inDays == 1) {
            final h = dt.hour.toString().padLeft(2, '0');
            final m = dt.minute.toString().padLeft(2, '0');
            return 'last seen yesterday at $h:$m';
          } else {
            final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
            final h = dt.hour.toString().padLeft(2, '0');
            final m = dt.minute.toString().padLeft(2, '0');
            return 'last seen ${months[dt.month - 1]} ${dt.day} at $h:$m';
          }
        }
        return 'last seen a long time ago';
      default:
        return 'last seen a long time ago';
    }
  }

  Color _statusColor(ContactInfo c) {
    if (c.isOnline || c.lastSeenKind == 'online') return _statusOnlineColor;
    if (_hovered) return widget.isDark ? _statusHoverNight : _statusHoverDay;
    return widget.isDark ? _statusOfflineNight : _statusOfflineDay;
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final isDark = widget.isDark;
    final contact = widget.contact;
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final iconColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF222222);
    final errorColor = const Color(0xFFe53935);
    final isContact = contact.isContact;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        if (!isContact)
          PopupMenuItem(value: 'add', child: Row(children: [
            Icon(Icons.person_add_alt_1, size: 20, color: iconColor),
            const SizedBox(width: 12),
            const Text('Add Contact'),
          ])),
        if (isContact)
          PopupMenuItem(value: 'edit', child: Row(children: [
            Icon(Icons.edit_outlined, size: 20, color: iconColor),
            const SizedBox(width: 12),
            const Text('Edit Contact'),
          ])),
        if (isContact)
          PopupMenuItem(value: 'share', child: Row(children: [
            Icon(Icons.person_add_alt_1, size: 20, color: iconColor),
            const SizedBox(width: 12),
            const Text('Share Contact'),
          ])),
        if (isContact)
          PopupMenuItem(value: 'delete', child: Row(children: [
            Icon(Icons.delete_outline, size: 20, color: errorColor),
            const SizedBox(width: 12),
            Text('Delete Contact', style: TextStyle(color: errorColor)),
          ])),
        if (!contact.isBot)
          PopupMenuItem(value: 'block', child: Row(children: [
            Icon(Icons.block, size: 20, color: errorColor),
            const SizedBox(width: 12),
            Text('Block User', style: TextStyle(color: errorColor)),
          ])),
      ],
    ).then((value) {
      if (value == null || !mounted) return;
      switch (value) {
        case 'add':
          final parts = contact.displayName.split(' ');
          final prefillFirst = contact.displayName.startsWith('@') ? '' : (parts.isNotEmpty ? parts.first : '');
          final prefillLast = contact.displayName.startsWith('@') ? '' : (parts.length > 1 ? parts.skip(1).join(' ') : '');
          showAddContactBox(
            context,
            initialPhone: contact.phone,
            initialFirstName: prefillFirst,
            initialLastName: prefillLast,
            initialUserId: contact.userId,
          );
        case 'edit':
          _editContact(contact, appState, engine);
        case 'share':
          _shareContact(contact, appState, engine);
        case 'delete':
          _deleteContact(contact, appState, engine);
        case 'block':
          _blockUser(contact, appState, engine);
      }
    });
  }

  void _shareContact(ContactInfo contact, AppState appState, EngineService engine) {
    showShareContactBox(
      context,
      contactPhone: contact.phone,
      contactFirstName: contact.displayName.split(' ').first,
      contactLastName: contact.displayName.split(' ').skip(1).join(' '),
      contactUserId: contact.userId,
    );
  }

  void _editContact(ContactInfo contact, AppState appState, EngineService engine) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => _EditContactBox(
        appState: appState,
        engine: engine,
        contact: contact,
      ),
    ).then((saved) {
      if (saved == true) {
        widget.onContactChanged?.call();
      }
    });
  }

  void _deleteContact(ContactInfo contact, AppState appState, EngineService engine) {
    final account = appState.activeAccount;
    if (account == null) return;
    showConfirmBox(
      context,
      text: 'Delete ${contact.label} from your contacts?',
      title: 'Delete Contact',
      confirmText: 'Delete',
      isDestructive: true,
      onConfirm: () async {
        await engine.deleteContact(account.id, contact.userId);
        widget.onContactChanged?.call();
      },
    );
  }

  void _blockUser(ContactInfo contact, AppState appState, EngineService engine) {
    final account = appState.activeAccount;
    if (account == null) return;
    showConfirmBox(
      context,
      text: 'Block ${contact.label}?',
      title: 'Block User',
      confirmText: 'Block',
      isDestructive: true,
      onConfirm: () async {
        await engine.blockUser(account.id, contact.userId);
        widget.onContactChanged?.call();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final contact = widget.contact;
    final palette = context.palette;
    final hasStories = contact.hasStories;
    final numId = int.tryParse(contact.userId) ?? contact.userId.hashCode.abs();
    final avatarColor = palette.peerUserpicBg(_colorRemap[numId.abs() % 7]);
    final initials = _initials(
        contact.displayName.isNotEmpty ? contact.displayName : contact.username);

    final ringStroke = contact.hasUnreadStory ? _ringStrokeUnread : _ringStrokeRead;
    final ringOuterSize = hasStories ? _avatarSize + (ringStroke + _ringGap) * 2 : _avatarSize;
    final baseAvatarLeft = hasStories ? _avatarLeftStory : _avatarLeft;
    final baseAvatarTop = hasStories ? _avatarTopStory : _avatarTop;
    final avatarOffsetX = hasStories ? baseAvatarLeft - (ringOuterSize - _avatarSize) / 2 : baseAvatarLeft;
    final avatarOffsetY = hasStories ? baseAvatarTop - (ringOuterSize - _avatarSize) / 2 : baseAvatarTop;
    final rowHeight = hasStories ? _rowHeightStory : _rowHeight;
    final nameLeft = hasStories ? _nameLeftStory : _nameLeft;
    final nameTop = hasStories ? _nameTopStory : _nameTop;
    final statusLeft = hasStories ? _statusLeftStory : _statusLeft;
    final statusTop = hasStories ? _statusTopStory : _statusTop;

    Widget avatarWidget = _avatarBytes != null
        ? ClipOval(
            child: Image.memory(
              _avatarBytes!,
              width: _avatarSize,
              height: _avatarSize,
              cacheWidth: (_avatarSize * MediaQuery.devicePixelRatioOf(context)).toInt(),
              cacheHeight: (_avatarSize * MediaQuery.devicePixelRatioOf(context)).toInt(),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _avatarFallback(avatarColor, initials),
            ),
          )
        : _avatarFallback(avatarColor, initials);

    Widget avatarArea;
    if (hasStories) {
      avatarArea = SizedBox(
        width: ringOuterSize,
        height: ringOuterSize,
        child: CustomPaint(
          painter: _ContactStoryRingPainter(
            storyCount: contact.storyCount,
            hasUnread: contact.hasUnreadStory,
            isDark: widget.isDark,
          ),
          child: Center(child: avatarWidget),
        ),
      );
      if (widget.onStoryTap != null) {
        avatarArea = GestureDetector(
          onTap: widget.onStoryTap,
          behavior: HitTestBehavior.opaque,
          child: avatarArea,
        );
      }
    } else {
      avatarArea = SizedBox(
        width: _avatarSize,
        height: _avatarSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            avatarWidget,
            if (contact.isOnline)
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _onlineColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _hovered ? widget.hoverBg : widget.bgColor,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final statusText = _statusText(contact);
    final statusColor = _statusColor(contact);

    final nameBadges = <InlineSpan>[];
    if (contact.isVerified) {
      nameBadges.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Icon(Icons.verified, size: 16, color: palette.profileVerifiedCheckBg),
        ),
      ));
    }
    if (contact.isPremium) {
      nameBadges.add(const WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: EdgeInsets.only(left: 4),
          child: Icon(Icons.star, size: 16, color: Color(0xFF8b5cf6)),
        ),
      ));
    }
    if (contact.isMutualContact) {
      nameBadges.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Icon(
            Icons.swap_horiz,
            size: 16,
            color: widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999),
          ),
        ),
      ));
    }
    if (contact.isScam) {
      nameBadges.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFe53935),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text('SCAM', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
          ),
        ),
      ));
    } else if (contact.isFake) {
      nameBadges.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFe53935),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text('FAKE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
          ),
        ),
      ));
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onTertiaryTapDown: (_) => (widget.onMiddleClick ?? widget.onTap)(),
        onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition),
        behavior: HitTestBehavior.opaque,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            color: _hovered ? widget.hoverBg : Colors.transparent,
            child: SizedBox(
              height: rowHeight,
              child: Stack(
                children: [
                  Positioned(
                    left: avatarOffsetX,
                    top: avatarOffsetY,
                    child: avatarArea,
                  ),
                  Positioned(
                    left: nameLeft,
                    top: nameTop,
                    right: _rightPad,
                    child: RichText(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        text: contact.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: widget.textColor,
                        ),
                        children: nameBadges,
                      ),
                    ),
                  ),
                  Positioned(
                    left: statusLeft,
                    top: statusTop,
                    right: _rightPad,
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 13,
                        color: statusColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _avatarFallback(Color color, String initials) {
    return Container(
      width: _avatarSize,
      height: _avatarSize,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: _avatarSize * 0.38,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static String _initials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return parts.first[0].toUpperCase();
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final Color textColor;
  final Color labelColor;
  final Color borderColor;
  final Color focusBorderColor;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;
  final int? maxLength;

  const _InputField({
    required this.controller,
    this.focusNode,
    required this.label,
    required this.textColor,
    required this.labelColor,
    required this.borderColor,
    required this.focusBorderColor,
    this.keyboardType,
    this.inputFormatters,
    this.onSubmitted,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      style: TextStyle(fontSize: 15, color: textColor),
      keyboardType: keyboardType,
      inputFormatters: [
        ...?inputFormatters,
        if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
      ],
      textInputAction: onSubmitted != null ? TextInputAction.next : null,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 14, color: labelColor),
        floatingLabelStyle: TextStyle(fontSize: 12, color: focusBorderColor),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: focusBorderColor, width: 2)),
      ),
    );
  }
}

class _ContactStoryRingPainter extends CustomPainter {
  final int storyCount;
  final bool hasUnread;
  final bool isDark;

  _ContactStoryRingPainter({
    required this.storyCount,
    required this.hasUnread,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (storyCount <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final lineWidth = hasUnread ? 2.0 : 1.0;
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
      const fullCircle = 5760.0;
      const separatorUnits = 160.0;
      final separatorRadians = (separatorUnits / fullCircle) * 2 * math.pi;
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
  bool shouldRepaint(_ContactStoryRingPainter old) =>
      storyCount != old.storyCount ||
      hasUnread != old.hasUnread ||
      isDark != old.isDark;
}

// ── Edit Contact Dialog (§33.6) ──

class _EditContactBox extends StatefulWidget {
  final AppState appState;
  final EngineService engine;
  final ContactInfo contact;

  const _EditContactBox({
    required this.appState,
    required this.engine,
    required this.contact,
  });

  @override
  State<_EditContactBox> createState() => _EditContactBoxState();
}

class _EditContactBoxState extends State<_EditContactBox> {
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _notesCtrl;
  late final FocusNode _firstNameFocus;
  late final FocusNode _lastNameFocus;
  late final FocusNode _notesFocus;
  bool _saving = false;
  String? _error;
  static const _notesMaxLength = 128;
  bool _hasPersonalPhoto = false;
  bool _hasBirthday = false;
  bool _sharePhone = true;
  bool _showSharePhone = false;
  Uint8List? _avatarBytes;

  String get _liveName {
    final first = _firstNameCtrl.text.trim();
    final last = _lastNameCtrl.text.trim();
    if (first.isEmpty && last.isEmpty) return widget.contact.displayName;
    return '$first $last'.trim();
  }

  @override
  void initState() {
    super.initState();
    final parts = _splitName(widget.contact.displayName);
    _firstNameCtrl = TextEditingController(text: parts.$1);
    _lastNameCtrl = TextEditingController(text: parts.$2);
    _notesCtrl = TextEditingController(text: widget.contact.note);
    _hasPersonalPhoto = widget.contact.hasPersonalPhoto;
    _hasBirthday = widget.contact.hasBirthday;
    final b64 = widget.contact.avatarB64;
    _avatarBytes = b64.isNotEmpty ? base64Decode(b64) : null;
    _firstNameFocus = FocusNode();
    _lastNameFocus = FocusNode();
    _notesFocus = FocusNode();
    _firstNameCtrl.addListener(_onNameChanged);
    _lastNameCtrl.addListener(_onNameChanged);
    _fetchFullInfo();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstNameFocus.requestFocus();
    });
  }

  Future<void> _fetchFullInfo() async {
    final account = widget.appState.activeAccount;
    if (account == null) return;
    try {
      final info = await widget.engine.getContactFullInfo(account.id, widget.contact.userId);
      if (!mounted) return;
      final note = info['note'] as String? ?? '';
      if (note.isNotEmpty && _notesCtrl.text.isEmpty) {
        _notesCtrl.text = note;
      }
      setState(() {
        _hasPersonalPhoto = info['has_personal_photo'] as bool? ?? false;
        final bDay = info['birthday_day'] as int? ?? 0;
        final bMonth = info['birthday_month'] as int? ?? 0;
        _hasBirthday = bDay > 0 && bMonth > 0;
        _showSharePhone = info['need_contacts_exception'] as bool? ?? false;
      });
    } catch (_) {}
  }

  void _onNameChanged() => setState(() {});

  static (String, String) _splitName(String displayName) {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return ('', '');
    final idx = trimmed.indexOf(' ');
    if (idx < 0) return (trimmed, '');
    return (trimmed.substring(0, idx), trimmed.substring(idx + 1).trim());
  }

  @override
  void dispose() {
    _firstNameCtrl.removeListener(_onNameChanged);
    _lastNameCtrl.removeListener(_onNameChanged);
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _notesCtrl.dispose();
    _firstNameFocus.dispose();
    _lastNameFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    if (firstName.isEmpty && lastName.isEmpty) {
      setState(() => _error = 'Please enter a name');
      return;
    }
    final account = widget.appState.activeAccount;
    if (account == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final phone = widget.contact.phone.isNotEmpty
          ? widget.contact.phone
          : '+0';
      final note = _notesCtrl.text.trim();
      await widget.engine.addContact(account.id, phone, firstName, lastName, note: note, userId: widget.contact.userId, sharePhone: _sharePhone && _showSharePhone);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _suggestPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    final account = widget.appState.activeAccount;
    if (account == null) return;
    try {
      await widget.engine.suggestContactPhoto(account.id, widget.contact.userId, path);
      if (mounted) showTelegramToast(context, 'Photo suggestion sent');
    } catch (e) {
      if (mounted) showTelegramToast(context, 'Failed: ${e.toString().replaceFirst("Exception: ", "")}');
    }
  }

  Future<void> _suggestBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Suggest Birthday',
    );
    if (picked == null || !mounted) return;
    final account = widget.appState.activeAccount;
    if (account == null) return;
    try {
      await widget.engine.suggestBirthday(
        account.id,
        widget.contact.userId,
        picked.day,
        picked.month,
        picked.year,
      );
      if (mounted) showTelegramToast(context, 'Birthday suggestion sent');
    } catch (e) {
      if (mounted) showTelegramToast(context, 'Failed: ${e.toString().replaceFirst("Exception: ", "")}');
    }
  }

  Future<void> _setPersonalPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    final account = widget.appState.activeAccount;
    if (account == null) return;
    try {
      await widget.engine.setPersonalContactPhoto(account.id, widget.contact.userId, path);
      if (mounted) showTelegramToast(context, 'Personal photo set');
    } catch (e) {
      if (mounted) showTelegramToast(context, 'Failed: ${e.toString().replaceFirst("Exception: ", "")}');
    }
  }

  Future<void> _clearPersonalPhoto() async {
    final account = widget.appState.activeAccount;
    if (account == null) return;
    try {
      await widget.engine.clearPersonalContactPhoto(account.id, widget.contact.userId);
      if (mounted) showTelegramToast(context, 'Photo reset to default');
    } catch (e) {
      if (mounted) showTelegramToast(context, 'Failed: ${e.toString().replaceFirst("Exception: ", "")}');
    }
  }

  void _confirmDelete() {
    final contact = widget.contact;
    final engine = widget.engine;
    final account = widget.appState.activeAccount;
    if (account == null) return;
    showConfirmBox(
      context,
      text: 'Are you sure you want to delete ${contact.label} from your contacts?',
      title: 'Delete Contact',
      confirmText: 'Delete',
      isDestructive: true,
      onConfirm: () {
        engine.deleteContact(account.id, contact.userId);
        if (mounted) Navigator.of(context).pop(true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final contact = widget.contact;

    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF222222);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final borderColor = isDark ? const Color(0xFF2B3A49) : const Color(0xFFDADADA);
    final focusBorderColor = isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);
    final buttonColor = isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE8E8E8);
    final settingsBtnBg = isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);

    final palette = context.palette;
    final numId = int.tryParse(contact.userId) ?? contact.userId.hashCode.abs();
    final avatarColor = palette.peerUserpicBg(_ContactRowState._colorRemap[numId.abs() % 7]);
    final initials = _ContactRowState._initials(
      contact.displayName.isNotEmpty ? contact.displayName : contact.username,
    );

    final phoneText = contact.phone.isNotEmpty
        ? _formatPhone(contact.phone)
        : 'Mobile hidden';

    return Dialog(
      backgroundColor: bgColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _boxWideWidth, minWidth: _boxWideWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title bar
            SizedBox(
              height: _boxTitleHeight,
              child: Row(
                children: [
                  const SizedBox(width: 24),
                  Expanded(
                    child: Text(
                      'Edit Contact',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, size: 20, color: subtextColor),
                    splashRadius: 16,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            // Cover: 108px height, avatar 72×72 at (19, 18), name at (109, 33), status at (109, 57)
            SizedBox(
              height: 108,
              child: Stack(
                children: [
                  Positioned(
                    left: 19,
                    top: 18,
                    child: _avatarBytes != null
                        ? ClipOval(
                            child: Image.memory(
                              _avatarBytes!,
                              width: 72,
                              height: 72,
                              cacheWidth: (72 * MediaQuery.devicePixelRatioOf(context)).toInt(),
                              cacheHeight: (72 * MediaQuery.devicePixelRatioOf(context)).toInt(),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _coverAvatarFallback(avatarColor, initials),
                            ),
                          )
                        : _coverAvatarFallback(avatarColor, initials),
                  ),
                  Positioned(
                    left: 109,
                    top: 33,
                    right: 16,
                    child: Text(
                      _liveName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Positioned(
                    left: 109,
                    top: 57,
                    right: 16,
                    child: Text(
                      phoneText,
                      style: TextStyle(fontSize: 13, color: subtextColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // Name fields
            Padding(
              padding: const EdgeInsets.fromLTRB(19, 0, 19, 10),
              child: _InputField(
                controller: _firstNameCtrl,
                focusNode: _firstNameFocus,
                label: 'First name',
                textColor: isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000),
                labelColor: subtextColor,
                borderColor: borderColor,
                focusBorderColor: focusBorderColor,
                maxLength: 64,
                onSubmitted: (_) => _lastNameFocus.requestFocus(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(19, 0, 19, 10),
              child: _InputField(
                controller: _lastNameCtrl,
                focusNode: _lastNameFocus,
                label: 'Last name',
                textColor: isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000),
                labelColor: subtextColor,
                borderColor: borderColor,
                focusBorderColor: focusBorderColor,
                maxLength: 64,
                onSubmitted: (_) => _save(),
              ),
            ),
            // Notes field
            Padding(
              padding: const EdgeInsets.fromLTRB(19, 0, 19, 10),
              child: TextField(
                controller: _notesCtrl,
                focusNode: _notesFocus,
                maxLines: 3,
                minLines: 1,
                maxLength: _notesMaxLength,
                style: TextStyle(fontSize: 15, color: isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000)),
                decoration: InputDecoration(
                  labelText: 'Notes',
                  labelStyle: TextStyle(fontSize: 14, color: subtextColor),
                  floatingLabelStyle: TextStyle(fontSize: 12, color: focusBorderColor),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: focusBorderColor, width: 2)),
                  counterStyle: TextStyle(fontSize: 11, color: subtextColor),
                ),
              ),
            ),
            if (_showSharePhone)
              Padding(
                padding: const EdgeInsets.fromLTRB(19, 4, 19, 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: _sharePhone,
                        onChanged: (v) => setState(() => _sharePhone = v ?? true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _sharePhone = !_sharePhone),
                        child: Text(
                          'Share my phone number',
                          style: TextStyle(fontSize: 14, color: isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.contact.isContact) ...[
              Divider(height: 1, color: dividerColor),
              if (!_hasBirthday && widget.contact.starsPerMessage == 0)
                _SettingsButtonRow(
                  icon: Icons.cake_outlined,
                  label: 'Suggest Birthday',
                  iconColor: buttonColor,
                  textColor: textColor,
                  hoverBg: settingsBtnBg,
                  onTap: _suggestBirthday,
                ),
              if (widget.contact.starsPerMessage == 0)
                _SettingsButtonRow(
                  icon: Icons.card_giftcard,
                  label: 'Suggest photo',
                  iconColor: buttonColor,
                  textColor: textColor,
                  hoverBg: settingsBtnBg,
                  onTap: _suggestPhoto,
                ),
              _SettingsButtonRow(
                icon: Icons.add_a_photo_outlined,
                label: 'Set personal photo',
                iconColor: buttonColor,
                textColor: textColor,
                hoverBg: settingsBtnBg,
                onTap: _setPersonalPhoto,
              ),
              if (_hasPersonalPhoto)
                _SettingsButtonRow(
                  icon: Icons.refresh,
                  label: 'Reset to default',
                  iconColor: buttonColor,
                  textColor: textColor,
                  hoverBg: settingsBtnBg,
                  onTap: _clearPersonalPhoto,
                ),
              Divider(height: 1, color: dividerColor),
              _SettingsButtonRow(
                icon: Icons.delete_outline,
                label: 'Delete Contact',
                iconColor: const Color(0xFFe53935),
                textColor: const Color(0xFFe53935),
                hoverBg: settingsBtnBg,
                onTap: _confirmDelete,
              ),
            ],
            if (_error != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(19, 4, 19, 0),
                child: Text(
                  _error!,
                  style: const TextStyle(fontSize: 13, color: Color(0xFFe53935)),
                ),
              ),
            ],
            // Footer buttons
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: buttonColor,
                      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _saving ? null : _save,
                    style: TextButton.styleFrom(
                      foregroundColor: buttonColor,
                      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    child: _saving
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: buttonColor),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _coverAvatarFallback(Color color, String initials) {
    return Container(
      width: 72,
      height: 72,
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

  static String _formatPhone(String phone) {
    if (phone.isEmpty) return '';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 3) return '+$digits';
    final buf = StringBuffer('+');
    for (var i = 0; i < digits.length; i++) {
      if (i == digits.length - 10 && digits.length > 10) {
        buf.write(' ');
      } else if (i > digits.length - 10) {
        if ((digits.length - i) == 7) buf.write(' ');
        if ((digits.length - i) == 4) buf.write(' ');
      }
      buf.write(digits[i]);
    }
    return buf.toString();
  }
}

class _SettingsButtonRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color textColor;
  final Color hoverBg;
  final VoidCallback onTap;

  const _SettingsButtonRow({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.textColor,
    required this.hoverBg,
    required this.onTap,
  });

  @override
  State<_SettingsButtonRow> createState() => _SettingsButtonRowState();
}

class _SettingsButtonRowState extends State<_SettingsButtonRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 41,
          padding: const EdgeInsets.only(left: 21, right: 20),
          color: _hovered ? widget.hoverBg : Colors.transparent,
          child: Row(
            children: [
              Icon(widget.icon, size: 24, color: widget.iconColor),
              const SizedBox(width: 15),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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

Future<void> showShareContactBox(
  BuildContext context, {
  required String contactPhone,
  required String contactFirstName,
  required String contactLastName,
  required String contactUserId,
}) {
  final appState = context.read<AppState>();
  final chatState = context.read<ChatState>();
  final engine = context.read<EngineService>();

  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      pageBuilder: (ctx, _, __) => _ShareContactBox(
        appState: appState,
        chatState: chatState,
        engine: engine,
        contactPhone: contactPhone,
        contactFirstName: contactFirstName,
        contactLastName: contactLastName,
        contactUserId: contactUserId,
      ),
    ),
  );
}

class _ShareContactBox extends StatefulWidget {
  final AppState appState;
  final ChatState chatState;
  final EngineService engine;
  final String contactPhone;
  final String contactFirstName;
  final String contactLastName;
  final String contactUserId;

  const _ShareContactBox({
    required this.appState,
    required this.chatState,
    required this.engine,
    required this.contactPhone,
    required this.contactFirstName,
    required this.contactLastName,
    required this.contactUserId,
  });

  @override
  State<_ShareContactBox> createState() => _ShareContactBoxState();
}

class _ShareContactBoxState extends State<_ShareContactBox> {
  static const _rowHeight = 108.0;
  static const _columnSkip = 6.0;
  static const _activateDuration = Duration(milliseconds: 150);
  static const _commentHeightMin = 36.0;
  static const _commentHeightMax = 72.0;
  static const _commentPadding = EdgeInsets.all(5);

  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];

  String _query = '';
  final Set<String> _selected = {};
  final _commentController = TextEditingController();
  bool _sending = false;
  List<ChatInfo>? _serverResults;
  Timer? _searchDebounce;

  List<ChatInfo> get _chats {
    final activeAccountId = widget.appState.activeAccountId;
    if (activeAccountId == null) return [];
    return widget.chatState.chatsForAccount(activeAccountId);
  }

  List<ChatInfo> get _sortedChats {
    final chats = List<ChatInfo>.from(_chats);
    final selfUserId = widget.appState.activeAccount?.selfUserId ?? '';
    final selfIdx = selfUserId.isNotEmpty
        ? chats.indexWhere((c) => c.chatId == selfUserId && c.type == ChatType.dm)
        : -1;
    if (selfIdx > 0) {
      final self = chats.removeAt(selfIdx);
      chats.insert(0, self);
    }
    return chats;
  }

  List<ChatInfo> get _filteredChats {
    final sorted = _sortedChats;
    if (_query.isEmpty) return sorted;
    final q = _query.toLowerCase();
    final local = sorted.where((c) => c.title.toLowerCase().contains(q)).toList();
    if (local.isEmpty && _serverResults != null && _serverResults!.isNotEmpty) {
      final localIds = sorted.map((c) => c.chatId).toSet();
      final extra = _serverResults!.where((c) => !localIds.contains(c.chatId)).toList();
      return [...local, ...extra];
    }
    return local;
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
    _searchDebounce?.cancel();
    if (value.trim().length >= 2) {
      _searchDebounce = Timer(const Duration(milliseconds: 300), () => _doServerSearch(value.trim()));
    } else {
      _serverResults = null;
    }
  }

  Future<void> _doServerSearch(String query) async {
    final accountId = widget.appState.activeAccountId;
    if (accountId == null) return;
    try {
      final results = await widget.engine.searchGlobalChats(accountId, query, limit: 20);
      if (mounted && _query == query) {
        setState(() => _serverResults = results);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _commentController.dispose();
    super.dispose();
  }

  void _toggleSelection(String chatId) {
    setState(() {
      if (_selected.contains(chatId)) {
        _selected.remove(chatId);
      } else {
        _selected.add(chatId);
      }
    });
  }

  Future<void> _doSend() async {
    if (_selected.isEmpty || _sending) return;
    setState(() => _sending = true);
    final accountId = widget.appState.activeAccountId;
    if (accountId == null) return;
    final comment = _commentController.text.trim();
    try {
      for (final chatId in _selected) {
        await widget.engine.sendContact(
          accountId,
          chatId,
          widget.contactPhone,
          widget.contactFirstName,
          widget.contactLastName,
          userId: widget.contactUserId,
        );
        if (comment.isNotEmpty) {
          await widget.engine.sendMessage(accountId, chatId, comment);
        }
      }
      if (mounted) {
        Navigator.of(context).pop();
        showTelegramToast(context, _selected.length == 1
            ? 'Contact shared'
            : 'Contact shared to ${_selected.length} chats');
      }
    } catch (e) {
      if (mounted) {
        showTelegramToast(context, 'Failed to share contact: $e');
        setState(() => _sending = false);
      }
    }
  }

  static const _columnCount = 4;

  static Color avatarColor(String id, TelegramPalette palette) {
    final numId = int.tryParse(id) ?? id.hashCode.abs();
    return palette.peerUserpicBg(_colorRemap[numId.abs() % 7]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final boxBg = palette.boxBg;
    final filtered = _filteredChats;
    final contactName = '${widget.contactFirstName} ${widget.contactLastName}'.trim();

    return Material(
      color: boxBg,
      child: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 54,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      'Share Contact',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 1,
              color: palette.shadowFg,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Sharing: $contactName',
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.boxTitleAdditionalFg,
                      ),
                    ),
                  ),
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: palette.windowBgOver,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _columnCount,
                  mainAxisExtent: _rowHeight,
                  crossAxisSpacing: _columnSkip,
                ),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final chat = filtered[index];
                  final isSelected = _selected.contains(chat.chatId);
                  return _ShareContactGridItem(
                    chat: chat,
                    isSelected: isSelected,
                    onTap: () => _toggleSelection(chat.chatId),
                  );
                },
              ),
            ),
            AnimatedSize(
              duration: _activateDuration,
              curve: Curves.easeOutCubic,
              child: _selected.isNotEmpty
                  ? Padding(
                      padding: _commentPadding,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: _commentHeightMin,
                          maxHeight: _commentHeightMax,
                        ),
                        child: TextField(
                          controller: _commentController,
                          maxLines: null,
                          decoration: InputDecoration(
                            hintText: 'Add a comment...',
                            isDense: true,
                            filled: true,
                            fillColor: palette.windowBgOver,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Container(
              height: 1,
              color: palette.shadowFg,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel', style: TextStyle(color: theme.hintColor)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _selected.isEmpty || _sending ? null : _doSend,
                    child: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            _selected.length <= 1
                                ? 'Send'
                                : 'Send (${_selected.length})',
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

class _ShareContactGridItem extends StatelessWidget {
  final ChatInfo chat;
  final bool isSelected;
  final VoidCallback onTap;

  const _ShareContactGridItem({
    required this.chat,
    required this.isSelected,
    required this.onTap,
  });

  static const _imageRadius = 28.0;
  static const _imageSmallRadius = 24.0;
  static const _photoTop = 6.0;
  static const _nameTop = 6.0;

  bool get _isSavedMessages =>
      chat.title == 'Saved Messages' && chat.type == ChatType.dm;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = isSelected ? _imageSmallRadius : _imageRadius;
    final accentColor = isDark ? const Color(0xFF6ab3f3) : const Color(0xFF40a7e3);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: _photoTop),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: (isSelected ? _imageSmallRadius : _imageRadius) * 2 + (isSelected ? 4 : 0),
            height: (isSelected ? _imageSmallRadius : _imageRadius) * 2 + (isSelected ? 4 : 0),
            decoration: isSelected
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: accentColor, width: 2),
                  )
                : null,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: radius * 2,
                height: radius * 2,
                child: _buildAvatar(radius, isDark, palette),
              ),
            ),
          ),
          SizedBox(height: _nameTop),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 150),
              style: TextStyle(
                fontSize: 11,
                color: isSelected
                    ? (isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd))
                    : (isDark ? const Color(0xFFdddddd) : const Color(0xFF333333)),
              ),
              child: Text(
                _isSavedMessages ? 'Saved Messages' : chat.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(double radius, bool isDark, TelegramPalette palette) {
    if (_isSavedMessages) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: isDark ? const Color(0xFF5288c1) : const Color(0xFF40a7e3),
        child: Icon(Icons.bookmark, color: Colors.white, size: radius),
      );
    }
    if (chat.avatarPath.isNotEmpty) {
      return ClipOval(
        child: Image.file(
          File(chat.avatarPath),
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackAvatar(radius, palette),
        ),
      );
    }
    return _fallbackAvatar(radius, palette);
  }

  Widget _fallbackAvatar(double radius, TelegramPalette palette) {
    final color = _ShareContactBoxState.avatarColor(chat.chatId, palette);
    final initials = chat.title.isNotEmpty ? chat.title[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        initials,
        style: TextStyle(color: Colors.white, fontSize: radius * 0.65),
      ),
    );
  }
}
