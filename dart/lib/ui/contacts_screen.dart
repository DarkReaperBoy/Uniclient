import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';

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
  String _searchQuery = '';
  _SortMode _sortMode = _SortMode.online;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    final all = _contacts ?? [];
    List<ContactInfo> filtered;
    if (_searchQuery.isEmpty) {
      filtered = all;
    } else {
      filtered = all.where((c) {
        return c.displayName.toLowerCase().contains(_searchQuery) ||
            c.username.toLowerCase().contains(_searchQuery) ||
            c.phone.contains(_searchQuery);
      }).toList();
    }
    return _sortedContacts(filtered);
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

    return Dialog(
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
            // Search field.
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(fontSize: 13, color: searchFg),
                  decoration: InputDecoration(
                    hintText: 'Search',
                    hintStyle: TextStyle(fontSize: 13, color: searchHintFg),
                    prefixIcon:
                        Icon(Icons.search, size: 18, color: searchHintFg),
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
            // Contact list.
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
                      : _filteredContacts.isEmpty
                          ? SizedBox(
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
                            )
                          : ListView.builder(
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
                                  onTap: () => _openChat(contact),
                                );
                              },
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
                    onPressed: () {
                      // TODO: open AddContactBox (§33.5)
                    },
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
    );
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
  final VoidCallback onTap;

  const _ContactRow({
    required this.contact,
    required this.textColor,
    required this.subtextColor,
    required this.hoverBg,
    required this.bgColor,
    required this.onTap,
  });

  @override
  State<_ContactRow> createState() => _ContactRowState();
}

class _ContactRowState extends State<_ContactRow> {
  bool _hovered = false;

  static const _rowHeight = 56.0;
  static const _avatarSize = 42.0;

  static const _avatarColors = [
    Color(0xFFE57373),
    Color(0xFF81C784),
    Color(0xFF64B5F6),
    Color(0xFFFFB74D),
    Color(0xFF9575CD),
    Color(0xFF4DB6AC),
    Color(0xFFF06292),
  ];

  @override
  Widget build(BuildContext context) {
    final contact = widget.contact;
    final colorIndex = contact.userId.hashCode.abs() % _avatarColors.length;
    final avatarColor = _avatarColors[colorIndex];
    final initials = _initials(
        contact.displayName.isNotEmpty ? contact.displayName : contact.username);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: _rowHeight,
          color: _hovered ? widget.hoverBg : Colors.transparent,
          padding: const EdgeInsets.only(left: 16, right: 16),
          child: Row(
            children: [
              SizedBox(
                width: _avatarSize,
                height: _avatarSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    contact.avatarB64.isNotEmpty
                        ? ClipOval(
                            child: Image.memory(
                              base64Decode(contact.avatarB64),
                              width: _avatarSize,
                              height: _avatarSize,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _avatarFallback(avatarColor, initials),
                            ),
                          )
                        : _avatarFallback(avatarColor, initials),
                    if (contact.isOnline)
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4dc920),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _hovered
                                  ? widget.hoverBg
                                  : widget.bgColor,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: widget.textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (contact.phone.isNotEmpty ||
                        contact.username.isNotEmpty)
                      Text(
                        contact.phone.isNotEmpty
                            ? contact.phone
                            : '@${contact.username}',
                        style: TextStyle(
                          fontSize: 13,
                          color: widget.subtextColor,
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

