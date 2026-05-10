import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../theme/theme.dart';
import '../utils/country_data.dart';
import 'confirm_box.dart';
import 'input_dialogs.dart';
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
      } else {
        final chats = engine.searchGlobalChats(account.id, query, limit: 10);
        if (mounted && _searchQuery == query && chats.isNotEmpty) {
          final existing = _contacts ?? [];
          final results = <ContactInfo>[];
          for (final chat in chats) {
            if (chat.type == ChatType.dm && !existing.any((c) => c.userId == chat.chatId)) {
              results.add(ContactInfo(
                userId: chat.chatId,
                displayName: chat.title,
              ));
            }
          }
          if (results.isNotEmpty) {
            setState(() => _globalResults = results);
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
    if (_sortMode != _SortMode.online) return;
    if (_sortThrottleTimer?.isActive == true) return;
    _sortThrottleTimer = Timer(_sortByOnlineThrottle, () {
      if (mounted) setState(() {});
    });
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
    showDialog<bool>(
      context: context,
      builder: (ctx) => ChangeNotifierProvider.value(
        value: context.read<AppState>(),
        child: Provider<EngineService>.value(
          value: context.read<EngineService>(),
          child: _AddContactBox(
            appState: context.read<AppState>(),
            engine: context.read<EngineService>(),
          ),
        ),
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
    } else {
      final syntheticDm = ChatInfo(
        accountId: context.read<AppState>().activeAccountId ?? '',
        chatId: contact.userId,
        title: contact.displayName.isNotEmpty ? contact.displayName : contact.username,
        type: ChatType.dm,
      );
      chatState.openChat(syntheticDm);
    }
    Navigator.of(context).pop();
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
                    color: _hovered ? hoverColor : Colors.transparent,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    widget.mode == _SortMode.online
                        ? Icons.sort_by_alpha
                        : Icons.access_time,
                    size: 22,
                    color: iconColor,
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
    final isContact = !contact.displayName.startsWith('@');
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
          showDialog<bool>(
            context: context,
            builder: (ctx) => ChangeNotifierProvider.value(
              value: context.read<AppState>(),
              child: Provider<EngineService>.value(
                value: context.read<EngineService>(),
                child: _AddContactBox(
                  appState: context.read<AppState>(),
                  engine: context.read<EngineService>(),
                ),
              ),
            ),
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
    );
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
      onConfirm: () {
        engine.deleteContact(account.id, contact.userId);
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
      onConfirm: () {
        engine.blockUser(account.id, contact.userId);
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
    if (digits == '333') return true;
    if (digits.startsWith('42') && (digits.length == 2 || digits.length == 4 || digits.length == 5 || digits.length == 6)) return true;
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
            // First name + last name fields with icon at contactIconPosition (-5, 23)
            Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                  ],
                ),
                Positioned(
                  left: 49 + (-5),
                  top: 23,
                  child: Icon(Icons.person, size: 24, color: labelColor),
                ),
              ],
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
  static const _itemHeight = 36.0;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    final idx = countries.indexWhere((c) => c.iso == widget.selected.iso);
    if (idx >= 0) _selectedIndex = idx;
    HardwareKeyboard.instance.addHandler(_hardwareKeyHandler);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_hardwareKeyHandler);
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  bool _hardwareKeyHandler(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final filtered = _filtered;
    if (filtered.isEmpty) return false;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(0, filtered.length - 1);
      });
      _ensureVisible(_selectedIndex);
      return true;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, filtered.length - 1);
      });
      _ensureVisible(_selectedIndex);
      return true;
    } else if (key == LogicalKeyboardKey.pageDown) {
      if (!_scrollCtrl.hasClients) return false;
      final pageItems = (_scrollCtrl.position.viewportDimension / _itemHeight).floor();
      setState(() {
        _selectedIndex = (_selectedIndex + pageItems).clamp(0, filtered.length - 1);
      });
      _ensureVisible(_selectedIndex);
      return true;
    } else if (key == LogicalKeyboardKey.pageUp) {
      if (!_scrollCtrl.hasClients) return false;
      final pageItems = (_scrollCtrl.position.viewportDimension / _itemHeight).floor();
      setState(() {
        _selectedIndex = (_selectedIndex - pageItems).clamp(0, filtered.length - 1);
      });
      _ensureVisible(_selectedIndex);
      return true;
    } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (_selectedIndex >= 0 && _selectedIndex < filtered.length) {
        widget.onSelect(filtered[_selectedIndex]);
      }
      return true;
    }
    return false;
  }

  void _ensureVisible(int index) {
    if (!_scrollCtrl.hasClients) return;
    final targetOffset = index * _itemHeight;
    final viewport = _scrollCtrl.position.viewportDimension;
    final current = _scrollCtrl.offset;
    if (targetOffset < current) {
      _scrollCtrl.jumpTo(targetOffset);
    } else if (targetOffset + _itemHeight > current + viewport) {
      _scrollCtrl.jumpTo(targetOffset + _itemHeight - viewport);
    }
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
                        itemExtent: _itemHeight,
                        itemBuilder: (ctx, i) {
                          final c = filtered[i];
                          return _CountryRow(
                            country: c,
                            textColor: textColor,
                            codeColor: subtextColor,
                            hoverBg: hoverBg,
                            isKeyboardSelected: i == _selectedIndex,
                            selectedBg: isDark ? const Color(0xFF2B3A49) : const Color(0xFFE3E3E3),
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
  final bool isKeyboardSelected;
  final Color selectedBg;
  final VoidCallback onTap;

  const _CountryRow({
    required this.country,
    required this.textColor,
    required this.codeColor,
    required this.hoverBg,
    this.isKeyboardSelected = false,
    this.selectedBg = Colors.transparent,
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
          color: _hovered ? widget.hoverBg : (widget.isKeyboardSelected ? widget.selectedBg : Colors.transparent),
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
  late final TextEditingController _notesCtrl;
  late final FocusNode _firstNameFocus;
  late final FocusNode _lastNameFocus;
  late final FocusNode _notesFocus;
  bool _saving = false;
  String? _error;
  static const _notesMaxLength = 70;

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
    _notesCtrl = TextEditingController();
    _firstNameFocus = FocusNode();
    _lastNameFocus = FocusNode();
    _notesFocus = FocusNode();
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
      await widget.engine.addContact(account.id, phone, firstName, lastName, note: note);
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
    final bytes = await File(path).readAsBytes();
    final account = widget.appState.activeAccount;
    if (account == null) return;
    try {
      await widget.engine.suggestContactPhoto(account.id, widget.contact.userId, bytes);
      if (mounted) showTelegramToast(context, 'Photo suggestion sent');
    } catch (e) {
      if (mounted) showTelegramToast(context, 'Failed: ${e.toString().replaceFirst("Exception: ", "")}');
    }
  }

  Future<void> _setPersonalPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    final account = widget.appState.activeAccount;
    if (account == null) return;
    try {
      await widget.engine.setPersonalContactPhoto(account.id, widget.contact.userId, bytes);
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
            // Photo management buttons
            Divider(height: 1, color: dividerColor),
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
            _SettingsButtonRow(
              icon: Icons.refresh,
              label: 'Reset to default',
              iconColor: buttonColor,
              textColor: textColor,
              hoverBg: settingsBtnBg,
              onTap: _clearPersonalPhoto,
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

  List<ChatInfo> get _chats {
    final activeAccountId = widget.appState.activeAccountId;
    if (activeAccountId == null) return [];
    return widget.chatState.chatsForAccount(activeAccountId);
  }

  List<ChatInfo> get _sortedChats {
    final chats = List<ChatInfo>.from(_chats);
    final selfIdx = chats.indexWhere(
      (c) => c.title == 'Saved Messages' && c.type == ChatType.dm,
    );
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
    return sorted.where((c) => c.title.toLowerCase().contains(q)).toList();
  }

  @override
  void dispose() {
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

  int _columnsForWidth(double screenWidth) {
    return (screenWidth / 90).floor().clamp(3, 10);
  }

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
    final size = MediaQuery.of(context).size;
    final colCount = _columnsForWidth(size.width);
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
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: colCount,
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
