import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../utils/country_data.dart';

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

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode();
    _loadContacts();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _globalSearchTimer?.cancel();
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
            setState(() {
              _globalResults = [
                ContactInfo(userId: result, username: username, displayName: '@$username'),
              ];
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

  List<ContactInfo> _sortedContacts(List<ContactInfo> list) {
    final sorted = List<ContactInfo>.from(list);
    switch (_sortMode) {
      case _SortMode.online:
        sorted.sort((a, b) {
          if (a.isOnline && !b.isOnline) return -1;
          if (!a.isOnline && b.isOnline) return 1;
          return a.label.toLowerCase().compareTo(b.label.toLowerCase());
        });
      case _SortMode.alphabetical:
        sorted.sort(
            (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    }
    return sorted;
  }

  List<ContactInfo> get _filteredContacts {
    final local = _localFiltered(_searchQuery);
    final sorted = _sortedContacts(local);
    if (_globalResults != null && _globalResults!.isNotEmpty) {
      final localIds = sorted.map((c) => c.userId).toSet();
      final extra = _globalResults!.where((c) => !localIds.contains(c.userId));
      return [...sorted, ...extra];
    }
    return sorted;
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
                  ? const SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator()),
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
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: ListView.builder(
                                    shrinkWrap: true,
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
                                        onStoryTap: contact.hasStories
                                            ? () => _openStory(contact)
                                            : null,
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
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    showDialog<bool>(
      context: context,
      builder: (ctx) => _AddContactBox(
        appState: appState,
        engine: engine,
      ),
    ).then((added) {
      if (added == true && mounted) {
        _loadContacts();
      }
    });
  }

  void _openChat(ContactInfo contact) {
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
      Navigator.of(context).pop();
    }
  }

  void _openStory(ContactInfo contact) {
    _openChat(contact);
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

class _SortToggleState extends State<_SortToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);
    final hoverColor = widget.isDark
        ? const Color(0xFF202B36)
        : const Color(0xFFF1F1F1);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onToggle,
        child: Container(
          width: 48,
          height: 54,
          alignment: Alignment.center,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hovered ? hoverColor : Colors.transparent,
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.mode == _SortMode.online
                  ? Icons.access_time
                  : Icons.sort_by_alpha,
              size: 22,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactRow extends StatefulWidget {
  final ContactInfo contact;
  final Color textColor;
  final Color subtextColor;
  final Color hoverBg;
  final Color bgColor;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onStoryTap;

  const _ContactRow({
    required this.contact,
    required this.textColor,
    required this.subtextColor,
    required this.hoverBg,
    required this.bgColor,
    required this.isDark,
    required this.onTap,
    this.onStoryTap,
  });

  @override
  State<_ContactRow> createState() => _ContactRowState();
}

class _ContactRowState extends State<_ContactRow> {
  bool _hovered = false;

  static const _rowHeight = 56.0;
  static const _avatarSize = 42.0;
  static const _avatarLeft = 16.0;
  static const _avatarTop = 7.0;
  static const _nameLeft = 74.0;
  static const _nameTop = 9.0;
  static const _statusLeft = 74.0;
  static const _statusTop = 30.0;
  static const _rightPad = 16.0;
  static const _ringStrokeUnread = 2.0;
  static const _ringStrokeRead = 1.0;
  static const _ringGap = 2.0;

  static const _avatarColors = [
    Color(0xFFE57373),
    Color(0xFF81C784),
    Color(0xFF64B5F6),
    Color(0xFFFFB74D),
    Color(0xFF9575CD),
    Color(0xFF4DB6AC),
    Color(0xFFF06292),
  ];

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
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem(value: 'edit', child: Row(children: [
          Icon(Icons.edit, size: 20, color: isDark ? const Color(0xFFF5F5F5) : const Color(0xFF222222)),
          const SizedBox(width: 12),
          const Text('Edit Contact'),
        ])),
        PopupMenuItem(value: 'share', child: Row(children: [
          Icon(Icons.person_add, size: 20, color: isDark ? const Color(0xFFF5F5F5) : const Color(0xFF222222)),
          const SizedBox(width: 12),
          const Text('Share Contact'),
        ])),
        PopupMenuItem(value: 'delete', child: Row(children: [
          Icon(Icons.delete, size: 20, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 12),
          Text('Delete Contact', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ])),
        if (!contact.isBot)
          PopupMenuItem(value: 'block', child: Row(children: [
            Icon(Icons.block, size: 20, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 12),
            Text('Block User', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ])),
      ],
    ).then((value) {
      if (value == null || !mounted) return;
      switch (value) {
        case 'edit':
          _editContact(contact, appState, engine);
        case 'delete':
          _deleteContact(contact, appState, engine);
        case 'block':
          _blockUser(contact, appState, engine);
        default:
          break;
      }
    });
  }

  void _editContact(ContactInfo contact, AppState appState, EngineService engine) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => _EditContactBox(
        appState: appState,
        engine: engine,
        contact: contact,
      ),
    );
  }

  void _deleteContact(ContactInfo contact, AppState appState, EngineService engine) {
    final account = appState.activeAccount;
    if (account == null) return;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Contact'),
        content: Text('Delete ${contact.label} from your contacts?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        engine.deleteContact(account.id, contact.userId);
      }
    });
  }

  void _blockUser(ContactInfo contact, AppState appState, EngineService engine) {
    final account = appState.activeAccount;
    if (account == null) return;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Block User'),
        content: Text('Block ${contact.label}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Block', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        engine.blockUser(account.id, contact.userId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final contact = widget.contact;
    final hasStories = contact.hasStories;
    final colorIndex = contact.userId.hashCode.abs() % _avatarColors.length;
    final avatarColor = _avatarColors[colorIndex];
    final initials = _initials(
        contact.displayName.isNotEmpty ? contact.displayName : contact.username);

    final ringStroke = contact.hasUnreadStory ? _ringStrokeUnread : _ringStrokeRead;
    final ringOuterSize = hasStories ? _avatarSize + (ringStroke + _ringGap) * 2 : _avatarSize;
    final avatarOffsetX = hasStories ? _avatarLeft - (ringOuterSize - _avatarSize) / 2 : _avatarLeft;
    final avatarOffsetY = hasStories ? _avatarTop - (ringOuterSize - _avatarSize) / 2 : _avatarTop;

    Widget avatarWidget = contact.avatarB64.isNotEmpty
        ? ClipOval(
            child: Image.memory(
              base64Decode(contact.avatarB64),
              width: _avatarSize,
              height: _avatarSize,
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
      nameBadges.add(const WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: EdgeInsets.only(left: 4),
          child: Icon(Icons.verified, size: 16, color: Color(0xFF40a7e3)),
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
        onTertiaryTapDown: (_) => widget.onTap(),
        onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition),
        behavior: HitTestBehavior.opaque,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            color: _hovered ? widget.hoverBg : Colors.transparent,
            child: SizedBox(
              height: _rowHeight,
              child: Stack(
                children: [
                  Positioned(
                    left: avatarOffsetX,
                    top: avatarOffsetY,
                    child: avatarArea,
                  ),
                  Positioned(
                    left: _nameLeft,
                    top: _nameTop,
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
                    left: _statusLeft,
                    top: _statusTop,
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

class _AddContactBox extends StatefulWidget {
  final AppState appState;
  final EngineService engine;

  const _AddContactBox({required this.appState, required this.engine});

  @override
  State<_AddContactBox> createState() => _AddContactBoxState();
}

class _AddContactBoxState extends State<_AddContactBox> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  late final FocusNode _firstNameFocus;
  late final FocusNode _lastNameFocus;
  late final FocusNode _phoneFocus;
  CountryInfo _selectedCountry = countries.firstWhere((c) => c.iso == 'US');
  bool _saving = false;
  String? _error;
  bool _retry = false;

  @override
  void initState() {
    super.initState();
    _firstNameFocus = FocusNode();
    _lastNameFocus = FocusNode();
    _phoneFocus = FocusNode();
    _codeCtrl.text = _selectedCountry.dialCode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstNameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _firstNameFocus.dispose();
    _lastNameFocus.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  bool _isValidPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits == '333' || RegExp(r'^42\d\d$').hasMatch(digits)) return true;
    return digits.length >= 8;
  }

  void _onCodeChanged(String val) {
    final code = val.replaceAll(RegExp(r'\D'), '');
    if (code.isEmpty) return;
    final match = countries.where((c) => c.dialCode == code).firstOrNull;
    if (match != null && match != _selectedCountry) {
      setState(() => _selectedCountry = match);
    }
  }

  void _showCountryPicker() {
    showDialog(
      context: context,
      builder: (ctx) => _CountrySelectBox(
        selected: _selectedCountry,
        onSelect: (country) {
          setState(() {
            _selectedCountry = country;
            _codeCtrl.text = country.dialCode;
          });
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  void _submit() {
    if (_retry) {
      _resetForm();
      return;
    }

    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    if (firstName.isEmpty && lastName.isEmpty) {
      setState(() => _error = 'Please enter a name');
      return;
    }

    final code = _codeCtrl.text.replaceAll(RegExp(r'\D'), '');
    final number = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    final fullPhone = '+$code$number';

    if (!_isValidPhone(number)) {
      setState(() => _error = 'Please enter a valid phone number');
      return;
    }

    _save(fullPhone, firstName, lastName);
  }

  void _resetForm() {
    setState(() {
      _firstNameCtrl.clear();
      _lastNameCtrl.clear();
      _phoneCtrl.clear();
      _error = null;
      _retry = false;
    });
    _firstNameFocus.requestFocus();
  }

  Future<void> _save(String phone, String firstName, String lastName) async {
    final account = widget.appState.activeAccount;
    if (account == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.engine.addContact(account.id, phone, firstName, lastName);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        if (msg.contains('not on Telegram') || msg.contains('PHONE_NOT_OCCUPIED') || msg.contains('no new users')) {
          setState(() {
            _saving = false;
            _error = 'This phone number is not on Telegram yet.';
            _retry = true;
          });
        } else {
          setState(() {
            _saving = false;
            _error = msg.replaceFirst('Exception: ', '');
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final labelColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final borderColor = isDark ? const Color(0xFF2B3A49) : const Color(0xFFDADADA);
    final focusBorderColor = isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);
    final buttonColor = isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);
    final errorColor = const Color(0xFFe53935);

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
            SizedBox(
              height: _boxTitleHeight,
              child: Row(
                children: [
                  const SizedBox(width: 24),
                  Text(
                    'Add Contact',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            // First name field
            Padding(
              padding: const EdgeInsets.fromLTRB(49, 0, 14, 0),
              child: _InputField(
                controller: _firstNameCtrl,
                focusNode: _firstNameFocus,
                label: 'First name',
                textColor: textColor,
                labelColor: labelColor,
                borderColor: borderColor,
                focusBorderColor: focusBorderColor,
                onSubmitted: (_) => _lastNameFocus.requestFocus(),
              ),
            ),
            const SizedBox(height: 9),
            // Last name field
            Padding(
              padding: const EdgeInsets.fromLTRB(49, 0, 14, 0),
              child: _InputField(
                controller: _lastNameCtrl,
                focusNode: _lastNameFocus,
                label: 'Last name',
                textColor: textColor,
                labelColor: labelColor,
                borderColor: borderColor,
                focusBorderColor: focusBorderColor,
                onSubmitted: (_) => _phoneFocus.requestFocus(),
              ),
            ),
            const SizedBox(height: 30),
            // Phone number with country code
            Padding(
              padding: const EdgeInsets.fromLTRB(49, 0, 14, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Country code trigger
                  Container(
                    width: 90,
                    height: 44,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: borderColor, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text('+', style: TextStyle(fontSize: 15, color: textColor)),
                        SizedBox(
                          width: 40,
                          child: TextField(
                            controller: _codeCtrl,
                            style: TextStyle(fontSize: 15, color: textColor),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 8),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                            onChanged: _onCodeChanged,
                          ),
                        ),
                        GestureDetector(
                          onTap: _showCountryPicker,
                          behavior: HitTestBehavior.opaque,
                          child: SizedBox(
                            width: 30,
                            height: 44,
                            child: Center(
                              child: Icon(Icons.arrow_drop_down, size: 20, color: labelColor),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Phone number
                  Expanded(
                    child: _InputField(
                      controller: _phoneCtrl,
                      focusNode: _phoneFocus,
                      label: 'Phone number',
                      textColor: textColor,
                      labelColor: labelColor,
                      borderColor: borderColor,
                      focusBorderColor: focusBorderColor,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [_PhoneNumberFormatter()],
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(49, 0, 14, 0),
                child: Text(
                  _error!,
                  style: TextStyle(fontSize: 13, color: errorColor),
                ),
              ),
            ],
            const SizedBox(height: 14),
            // Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: buttonColor,
                      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _saving ? null : _submit,
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
                        : Text(_retry ? 'Try Other Contact' : 'Add'),
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
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      style: TextStyle(fontSize: 15, color: textColor),
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
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

class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    }
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 3 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();
    final digitsBeforeCursor = newValue.text
        .substring(0, newValue.selection.end.clamp(0, newValue.text.length))
        .replaceAll(RegExp(r'\D'), '')
        .length;
    var cursor = 0;
    var count = 0;
    for (var i = 0; i < formatted.length && count < digitsBeforeCursor; i++) {
      cursor = i + 1;
      if (formatted[i] != ' ') count++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursor.clamp(0, formatted.length)),
    );
  }
}

class _CountrySelectBox extends StatefulWidget {
  final CountryInfo selected;
  final void Function(CountryInfo) onSelect;

  const _CountrySelectBox({required this.selected, required this.onSelect});

  @override
  State<_CountrySelectBox> createState() => _CountrySelectBoxState();
}

class _CountrySelectBoxState extends State<_CountrySelectBox> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  int _selectedIndex = 0;
  late final ScrollController _scrollCtrl;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    final idx = countries.indexWhere((c) => c.iso == widget.selected.iso);
    if (idx >= 0) _selectedIndex = idx;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<CountryInfo> get _filtered {
    if (_query.isEmpty) return countries.toList();
    final queryWords = _query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return countries.where((c) {
      final nameLower = c.name.toLowerCase();
      final nameWords = nameLower.split(RegExp(r'[\s\-]+'));
      for (final qw in queryWords) {
        final matchesWord = nameWords.any((w) => w.startsWith(qw));
        final matchesCode = c.dialCode.startsWith(qw);
        final matchesIso = c.iso.toLowerCase().startsWith(qw);
        if (!matchesWord && !matchesCode && !matchesIso) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final hoverBg = isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);
    final searchBg = isDark ? const Color(0xFF242F3D) : const Color(0xFFF1F1F1);
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE8E8E8);
    final buttonColor = isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);
    final filtered = _filtered;

    return Dialog(
      backgroundColor: bgColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 54,
              child: Row(
                children: [
                  const SizedBox(width: 24),
                  Text(
                    'Choose a country',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  style: TextStyle(fontSize: 13, color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Search',
                    hintStyle: TextStyle(fontSize: 13, color: subtextColor),
                    prefixIcon: Icon(Icons.search, size: 18, color: subtextColor),
                    filled: true,
                    fillColor: searchBg,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                  ),
                  onChanged: (v) {
                    setState(() {
                      _query = v.toLowerCase().trim();
                      _selectedIndex = 0;
                    });
                  },
                ),
              ),
            ),
            Divider(height: 1, color: dividerColor),
            Flexible(
              child: filtered.isEmpty
                  ? SizedBox(
                      height: 100,
                      child: Center(
                        child: Text('No countries found', style: TextStyle(fontSize: 14, color: subtextColor)),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemExtent: 36,
                      itemBuilder: (ctx, i) {
                        final c = filtered[i];
                        return _CountryRow(
                          country: c,
                          textColor: textColor,
                          codeColor: subtextColor,
                          hoverBg: hoverBg,
                          onTap: () => widget.onSelect(c),
                        );
                      },
                    ),
            ),
            Divider(height: 1, color: dividerColor),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountryRow extends StatefulWidget {
  final CountryInfo country;
  final Color textColor;
  final Color codeColor;
  final Color hoverBg;
  final VoidCallback onTap;

  const _CountryRow({
    required this.country,
    required this.textColor,
    required this.codeColor,
    required this.hoverBg,
    required this.onTap,
  });

  @override
  State<_CountryRow> createState() => _CountryRowState();
}

class _CountryRowState extends State<_CountryRow> {
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
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: _hovered ? widget.hoverBg : Colors.transparent,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.country.name,
                  style: TextStyle(fontSize: 14, color: widget.textColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '+${widget.country.dialCode}',
                style: TextStyle(fontSize: 14, color: widget.codeColor),
              ),
            ],
          ),
        ),
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
        colors: [Color(0xFF34c76e), Color(0xFF3da1fd)],
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
  late final FocusNode _firstNameFocus;
  late final FocusNode _lastNameFocus;
  bool _saving = false;
  String? _error;

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
    _firstNameFocus = FocusNode();
    _lastNameFocus = FocusNode();
    _firstNameCtrl.addListener(_onNameChanged);
    _lastNameCtrl.addListener(_onNameChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstNameFocus.requestFocus();
    });
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
    _firstNameFocus.dispose();
    _lastNameFocus.dispose();
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
      await widget.engine.addContact(account.id, phone, firstName, lastName);
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

  void _confirmDelete() {
    final contact = widget.contact;
    final engine = widget.engine;
    final account = widget.appState.activeAccount;
    if (account == null) return;
    showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
        final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
        final buttonColor = isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);
        return Dialog(
          backgroundColor: bgColor,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Delete Contact',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Are you sure you want to delete ${contact.label} from your contacts?',
                    style: TextStyle(fontSize: 14, color: textColor),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: TextButton.styleFrom(foregroundColor: buttonColor),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFe53935)),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((confirmed) {
      if (confirmed == true) {
        engine.deleteContact(account!.id, contact.userId);
        if (mounted) Navigator.of(context).pop(true);
      }
    });
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

    final colorIndex = contact.userId.hashCode.abs() % _ContactRowState._avatarColors.length;
    final avatarColor = _ContactRowState._avatarColors[colorIndex];
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
                    child: contact.avatarB64.isNotEmpty
                        ? ClipOval(
                            child: Image.memory(
                              base64Decode(contact.avatarB64),
                              width: 72,
                              height: 72,
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
                onSubmitted: (_) => _save(),
              ),
            ),
            // Photo management buttons
            Divider(height: 1, color: dividerColor),
            _SettingsButtonRow(
              icon: Icons.add_a_photo_outlined,
              label: 'Set personal photo',
              iconColor: buttonColor,
              textColor: textColor,
              hoverBg: settingsBtnBg,
              onTap: () {},
            ),
            _SettingsButtonRow(
              icon: Icons.refresh,
              label: 'Reset to default',
              iconColor: buttonColor,
              textColor: textColor,
              hoverBg: settingsBtnBg,
              onTap: () {},
            ),
            Divider(height: 1, color: dividerColor),
            // Delete contact
            _SettingsButtonRow(
              icon: Icons.delete_outline,
              label: 'Delete Contact',
              iconColor: const Color(0xFFe53935),
              textColor: const Color(0xFFe53935),
              hoverBg: settingsBtnBg,
              onTap: _confirmDelete,
            ),
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

