import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';

/// Contacts screen (§3.3). Opened from hamburger drawer "Contacts" row.
/// Displays the user's contact list, sorted alphabetically, with search.
/// Each row: circular avatar + name + phone number.
/// Tapping a contact opens the DM chat with that user.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<ContactInfo>? _contacts;
  String _error = '';
  bool _loading = true;
  final _searchController = TextEditingController();
  String _searchQuery = '';

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
      // Sort alphabetically by display name.
      contacts.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
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

  List<ContactInfo> get _filteredContacts {
    final all = _contacts ?? [];
    if (_searchQuery.isEmpty) return all;
    return all.where((c) {
      return c.displayName.toLowerCase().contains(_searchQuery) ||
          c.username.toLowerCase().contains(_searchQuery) ||
          c.phone.contains(_searchQuery);
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
    final searchFg = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final searchHintFg = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE8E8E8);

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
          'Contacts',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search bar.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _searchController,
                style: TextStyle(fontSize: 13, color: searchFg),
                decoration: InputDecoration(
                  hintText: 'Search',
                  hintStyle: TextStyle(fontSize: 13, color: searchHintFg),
                  prefixIcon: Icon(Icons.search, size: 18, color: searchHintFg),
                  filled: true,
                  fillColor: searchBg,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
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
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty
                    ? Center(
                        child: Text(
                          _error,
                          style: TextStyle(color: subtextColor, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : _filteredContacts.isEmpty
                        ? Center(
                            child: Text(
                              _searchQuery.isNotEmpty
                                  ? 'No contacts found'
                                  : 'No contacts yet',
                              style: TextStyle(color: subtextColor, fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _filteredContacts.length,
                            itemBuilder: (context, index) {
                              final contact = _filteredContacts[index];
                              return _ContactRow(
                                contact: contact,
                                textColor: textColor,
                                subtextColor: subtextColor,
                                hoverBg: hoverBg,
                                onTap: () => _openChat(contact),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  void _openChat(ContactInfo contact) {
    final chatState = context.read<ChatState>();
    // Find the DM chat for this contact by user ID.
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

class _ContactRow extends StatefulWidget {
  final ContactInfo contact;
  final Color textColor;
  final Color subtextColor;
  final Color hoverBg;
  final VoidCallback onTap;

  const _ContactRow({
    required this.contact,
    required this.textColor,
    required this.subtextColor,
    required this.hoverBg,
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
    Color(0xFFE57373), // red
    Color(0xFF81C784), // green
    Color(0xFF64B5F6), // blue
    Color(0xFFFFB74D), // orange
    Color(0xFF9575CD), // purple
    Color(0xFF4DB6AC), // teal
    Color(0xFFF06292), // pink
  ];

  @override
  Widget build(BuildContext context) {
    final contact = widget.contact;
    final colorIndex = contact.userId.hashCode.abs() % _avatarColors.length;
    final avatarColor = _avatarColors[colorIndex];
    final initials = _initials(contact.displayName.isNotEmpty
        ? contact.displayName
        : contact.username);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: _rowHeight,
          color: _hovered ? widget.hoverBg : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // Avatar.
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
                                  : Theme.of(context).colorScheme.surface,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Name + phone/username.
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.label,
                      style: TextStyle(
                        fontSize: 14,
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
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
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
