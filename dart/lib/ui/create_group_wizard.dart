import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';

/// §21: Create Group / Channel Wizard.
/// Multi-step layered-box flow, all boxes 364px (boxWideWidth).
/// Group flow:   InfoBox → MemberPicker → create → navigate.
/// Channel flow: InfoBox → create → SetupChannelBox → MemberPicker → navigate.

enum _WizardType { group, channel }

enum _WizardStep { info, setupChannel, memberPicker }

const double _boxWidth = 364;
const double _boxTitleHeight = 48;
const EdgeInsets _boxPadding = EdgeInsets.fromLTRB(24, 14, 24, 8);
const int _maxTitleLength = 128;
const int _maxDescLength = 255;

// §21.2.1: 8 userpic gradient pairs.
const List<List<Color>> _userpicGradients = [
  [Color(0xFFFC5C51), Color(0xFFE44234)],
  [Color(0xFFCB86DB), Color(0xFF9338AF)],
  [Color(0xFF4AB5E3), Color(0xFF377EB5)],
  [Color(0xFF85C255), Color(0xFF549B3B)],
  [Color(0xFFF68136), Color(0xFFDE5B2D)],
  [Color(0xFFEC5481), Color(0xFFBB2F60)],
  [Color(0xFF6EC0ED), Color(0xFF2896C4)],
  [Color(0xFFF7B74A), Color(0xFFE68E2B)],
];

Future<void> showCreateGroupWizard(BuildContext context) {
  return _showWizard(context, _WizardType.group);
}

Future<void> showCreateChannelWizard(BuildContext context) {
  return _showWizard(context, _WizardType.channel);
}

Future<void> _showWizard(BuildContext context, _WizardType type) {
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
          child: _WizardDialog(type: type),
        ),
      ),
    ),
  );
}

class _WizardDialog extends StatefulWidget {
  final _WizardType type;
  const _WizardDialog({required this.type});

  @override
  State<_WizardDialog> createState() => _WizardDialogState();
}

class _WizardDialogState extends State<_WizardDialog> {
  late _WizardStep _step;
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _nameFocus = FocusNode();
  bool _creating = false;
  String? _error;
  String _createdChatId = '';

  // Member picker state.
  List<ContactInfo> _contacts = [];
  final Set<String> _selectedMembers = {};
  final _memberSearchController = TextEditingController();
  bool _loadingContacts = false;

  // Channel setup state.
  bool _isPublic = false;
  final _usernameController = TextEditingController();
  String? _usernameStatus;
  bool _usernameValid = false;

  @override
  void initState() {
    super.initState();
    _step = _WizardStep.info;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _nameFocus.dispose();
    _memberSearchController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  String get _accountId => context.read<AppState>().activeAccountId;
  EngineService get _engine => context.read<EngineService>();
  ChatState get _chatState => context.read<ChatState>();

  Uint8List? _photoBytes;
  String? _photoPath;
  double _uploadProgress = -1;

  List<Color> get _userpicColors {
    final name = _nameController.text.trim();
    final idx = name.isEmpty ? 0 : name.codeUnitAt(0) % _userpicGradients.length;
    return _userpicGradients[idx];
  }

  static final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

  String get _userpicInitials {
    final name = _nameController.text.trim();
    if (name.isEmpty) return '';

    String? first;
    for (int i = 0; i < name.length; i++) {
      final c = name.codeUnitAt(i);
      if (c >= 0xD800 && c <= 0xDFFF) continue;
      if (_letterOrDigit.hasMatch(name[i])) {
        first = name[i].toUpperCase();
        break;
      }
    }
    if (first == null) return '';

    String? afterSpace, afterHyphen;
    for (int i = 1; i < name.length; i++) {
      final c = name.codeUnitAt(i);
      if (c >= 0xD800 && c <= 0xDFFF) continue;
      if (!_letterOrDigit.hasMatch(name[i])) continue;
      if (name[i - 1] == ' ' && afterSpace == null) {
        afterSpace = name[i].toUpperCase();
      }
      if (name[i - 1] == '-' && afterHyphen == null) {
        afterHyphen = name[i].toUpperCase();
      }
    }

    final second = afterSpace ?? afterHyphen;
    return second != null ? '$first$second' : first;
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    try {
      final bytes = await File(path).readAsBytes();
      if (!mounted) return;
      setState(() {
        _photoBytes = bytes;
        _photoPath = path;
      });
    } catch (_) {}
  }

  void _onUserpicTap() {
    if (_photoBytes != null) {
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remove Photo'),
          content: const Text('Choose a new photo or remove the current one?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Choose New'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ).then((remove) {
        if (remove == true) {
          setState(() {
            _photoBytes = null;
            _photoPath = null;
          });
        } else if (remove == false) {
          _pickPhoto();
        }
      });
    } else {
      _pickPhoto();
    }
  }

  Future<void> _loadContacts() async {
    if (_loadingContacts) return;
    setState(() => _loadingContacts = true);
    try {
      final contacts = await _engine.getContacts(_accountId);
      if (!mounted) return;
      setState(() {
        _contacts = contacts.where((c) => !c.isBot).toList();
        _loadingContacts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingContacts = false);
    }
  }

  Future<void> _submitInfo() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _nameFocus.requestFocus();
      setState(() => _error = 'Please enter a name');
      return;
    }

    if (widget.type == _WizardType.group) {
      _loadContacts();
      setState(() {
        _step = _WizardStep.memberPicker;
        _error = null;
      });
    } else {
      setState(() {
        _creating = true;
        _error = null;
      });
      try {
        final chatInfo = await _engine.createChannel(
          _accountId,
          name,
          _descController.text.trim(),
        );
        if (!mounted) return;
        _createdChatId = chatInfo.chatId;
        setState(() {
          _creating = false;
          _step = _WizardStep.setupChannel;
        });
      } on EngineException catch (e) {
        if (!mounted) return;
        String msg = e.message;
        if (msg.contains('NO_CHAT_TITLE')) msg = 'Please enter a channel name';
        if (msg.contains('CHANNELS_TOO_MUCH')) msg = 'You have created too many channels';
        setState(() { _creating = false; _error = msg; });
      } catch (e) {
        if (!mounted) return;
        setState(() { _creating = false; _error = e.toString(); });
      }
    }
  }

  Future<void> _submitGroup() async {
    setState(() { _creating = true; _error = null; });
    try {
      final result = await _engine.createGroup(
        _accountId,
        _nameController.text.trim(),
        _selectedMembers.toList(),
      );
      if (!mounted) return;
      final chatId = result['chat_id'] as String? ?? '';
      if (chatId.isNotEmpty) {
        final chat = _chatState.chats.where((c) => c.chatId == chatId).firstOrNull;
        if (chat != null) _chatState.openChat(chat);
      }
      Navigator.of(context).pop();
    } on EngineException catch (e) {
      if (!mounted) return;
      setState(() { _creating = false; _error = e.message; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _creating = false; _error = e.toString(); });
    }
  }

  Future<void> _finishChannelSetup() async {
    if (_createdChatId.isNotEmpty) {
      _loadContacts();
      setState(() {
        _step = _WizardStep.memberPicker;
        _error = null;
      });
    }
  }

  Future<void> _inviteMembers() async {
    if (_createdChatId.isEmpty || _selectedMembers.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop();
    final chat = _chatState.chats.where((c) => c.chatId == _createdChatId).firstOrNull;
    if (chat != null) _chatState.openChat(chat);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: _boxWidth,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(3),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTitleBar(isDark),
              Flexible(
                child: SingleChildScrollView(
                  padding: _boxPadding,
                  child: _buildStepContent(isDark),
                ),
              ),
              _buildButtons(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar(bool isDark) {
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    String title;
    switch (_step) {
      case _WizardStep.info:
        title = widget.type == _WizardType.group ? 'New Group' : 'New Channel';
      case _WizardStep.setupChannel:
        title = 'Channel Type';
      case _WizardStep.memberPicker:
        title = widget.type == _WizardType.group ? 'Add Members' : 'Add Subscribers';
    }

    return Container(
      height: _boxTitleHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0x14FFFFFF) : const Color(0x14000000),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
          if (_step == _WizardStep.memberPicker && _selectedMembers.isNotEmpty)
            Text(
              '${_selectedMembers.length}',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFF6C7883) : const Color(0xFF999999),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepContent(bool isDark) {
    switch (_step) {
      case _WizardStep.info:
        return _buildInfoStep(isDark);
      case _WizardStep.setupChannel:
        return _buildSetupChannelStep(isDark);
      case _WizardStep.memberPicker:
        return _buildMemberPickerStep(isDark);
    }
  }

  Widget _buildInfoStep(bool isDark) {
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final fieldBg = isDark ? const Color(0xFF242F3D) : const Color(0xFFF1F1F1);
    final colors = _userpicColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _UserpicButton(
              size: 72,
              gradientColors: colors,
              initials: _userpicInitials,
              photoBytes: _photoBytes,
              uploadProgress: _uploadProgress,
              onTap: (_) => _onUserpicTap(),
            ),
            const SizedBox(width: 27),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: TextField(
                  controller: _nameController,
                  focusNode: _nameFocus,
                  maxLength: _maxTitleLength,
                  style: TextStyle(fontSize: 14, color: textColor),
                  decoration: InputDecoration(
                    hintText: widget.type == _WizardType.group
                        ? 'Group Name'
                        : 'Channel Name',
                    hintStyle: TextStyle(color: subtextColor),
                    counterText: '',
                    filled: true,
                    fillColor: fieldBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
            ),
          ],
        ),
        if (widget.type == _WizardType.channel) ...[
          const SizedBox(height: 13),
          TextField(
            controller: _descController,
            maxLength: _maxDescLength,
            maxLines: null,
            minLines: 3,
            style: TextStyle(fontSize: 14, color: textColor),
            decoration: InputDecoration(
              hintText: 'Description (optional)',
              hintStyle: TextStyle(color: subtextColor),
              counterText: '',
              filled: true,
              fillColor: fieldBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You can provide an optional description for your channel.',
            style: TextStyle(fontSize: 13, color: subtextColor),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(fontSize: 13, color: Color(0xFFDD4B39)),
          ),
        ],
      ],
    );
  }

  Widget _buildSetupChannelStep(bool isDark) {
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);
    final fieldBg = isDark ? const Color(0xFF242F3D) : const Color(0xFFF1F1F1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _RadioRow(
          label: 'Public Channel',
          subtitle: 'Anyone can find the channel and join',
          selected: _isPublic,
          onTap: () => setState(() => _isPublic = true),
          isDark: isDark,
        ),
        const SizedBox(height: 27),
        _RadioRow(
          label: 'Private Channel',
          subtitle: 'Only accessible via invite link',
          selected: !_isPublic,
          onTap: () => setState(() => _isPublic = false),
          isDark: isDark,
        ),
        const SizedBox(height: 16),
        if (_isPublic) ...[
          Text(
            'Public Link',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                't.me/',
                style: TextStyle(fontSize: 14, color: subtextColor),
              ),
              Expanded(
                child: TextField(
                  controller: _usernameController,
                  style: TextStyle(fontSize: 14, color: textColor),
                  decoration: InputDecoration(
                    hintText: 'link',
                    hintStyle: TextStyle(color: subtextColor),
                    filled: true,
                    fillColor: fieldBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    isDense: true,
                  ),
                  onChanged: (_) {
                    setState(() {
                      _usernameStatus = null;
                      _usernameValid = false;
                    });
                  },
                ),
              ),
            ],
          ),
          if (_usernameStatus != null) ...[
            const SizedBox(height: 8),
            Text(
              _usernameStatus!,
              style: TextStyle(
                fontSize: 13,
                color: _usernameValid
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFDD4B39),
              ),
            ),
          ],
        ] else ...[
          Text(
            'People can join your channel by following this link. '
            'You can revoke the link any time.',
            style: TextStyle(fontSize: 13, color: subtextColor),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(fontSize: 13, color: Color(0xFFDD4B39)),
          ),
        ],
      ],
    );
  }

  Widget _buildMemberPickerStep(bool isDark) {
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final fieldBg = isDark ? const Color(0xFF242F3D) : const Color(0xFFF1F1F1);
    final accentColor = isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);
    final searchText = _memberSearchController.text.toLowerCase();

    final filtered = searchText.isEmpty
        ? _contacts
        : _contacts.where((c) {
            return c.displayName.toLowerCase().contains(searchText) ||
                c.username.toLowerCase().contains(searchText) ||
                c.phone.contains(searchText);
          }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_selectedMembers.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _selectedMembers.map((id) {
              final contact = _contacts.where((c) => c.userId == id).firstOrNull;
              final name = contact?.displayName ?? id;
              return Chip(
                label: Text(
                  name,
                  style: TextStyle(fontSize: 12, color: textColor),
                  overflow: TextOverflow.ellipsis,
                ),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => setState(() => _selectedMembers.remove(id)),
                backgroundColor: fieldBg,
                side: BorderSide.none,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _memberSearchController,
          style: TextStyle(fontSize: 14, color: textColor),
          decoration: InputDecoration(
            hintText: 'Search',
            hintStyle: TextStyle(color: subtextColor),
            prefixIcon: Icon(Icons.search, color: subtextColor, size: 20),
            filled: true,
            fillColor: fieldBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        if (_loadingContacts)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                _contacts.isEmpty ? 'No contacts found' : 'No matches',
                style: TextStyle(fontSize: 13, color: subtextColor),
              ),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: filtered.length,
              itemBuilder: (ctx, i) {
                final c = filtered[i];
                final selected = _selectedMembers.contains(c.userId);
                return _ContactRow(
                  contact: c,
                  selected: selected,
                  isDark: isDark,
                  onTap: () {
                    setState(() {
                      if (selected) {
                        _selectedMembers.remove(c.userId);
                      } else {
                        _selectedMembers.add(c.userId);
                      }
                    });
                  },
                );
              },
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(fontSize: 13, color: Color(0xFFDD4B39)),
          ),
        ],
      ],
    );
  }

  Widget _buildButtons(bool isDark) {
    final accentColor = isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);
    final cancelColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

    String confirmLabel;
    VoidCallback? confirmAction;
    String cancelLabel = 'Cancel';
    VoidCallback cancelAction = () => Navigator.of(context).pop();

    switch (_step) {
      case _WizardStep.info:
        confirmLabel = widget.type == _WizardType.group ? 'Next' : 'Create';
        confirmAction = _creating ? null : _submitInfo;
      case _WizardStep.setupChannel:
        confirmLabel = 'Save';
        confirmAction = _finishChannelSetup;
        cancelLabel = 'Skip';
        cancelAction = () {
          _loadContacts();
          setState(() {
            _step = _WizardStep.memberPicker;
            _error = null;
          });
        };
      case _WizardStep.memberPicker:
        if (widget.type == _WizardType.group) {
          confirmLabel = 'Create';
          confirmAction = _creating ? null : _submitGroup;
        } else {
          confirmLabel = 'Invite';
          confirmAction =
              _selectedMembers.isEmpty ? null : () => _inviteMembers();
          cancelLabel = 'Skip';
          cancelAction = () {
            final chat = _chatState.chats
                .where((c) => c.chatId == _createdChatId)
                .firstOrNull;
            if (chat != null) _chatState.openChat(chat);
            Navigator.of(context).pop();
          };
        }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: cancelAction,
            child: Text(
              cancelLabel,
              style: TextStyle(fontSize: 14, color: cancelColor),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: confirmAction,
            child: _creating
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accentColor,
                    ),
                  )
                : Text(
                    confirmLabel,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: confirmAction == null
                          ? cancelColor
                          : accentColor,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;

  const _RadioRow({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? accentColor : subtextColor,
                  width: selected ? 6 : 2,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: subtextColor),
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

class _ContactRow extends StatelessWidget {
  final ContactInfo contact;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _ContactRow({
    required this.contact,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);

    Widget avatar;
    if (contact.avatarB64.isNotEmpty) {
      try {
        final bytes = base64Decode(contact.avatarB64);
        avatar = CircleAvatar(
          radius: 21,
          backgroundImage: MemoryImage(bytes),
        );
      } catch (_) {
        avatar = _fallbackAvatar(contact, isDark);
      }
    } else {
      avatar = _fallbackAvatar(contact, isDark);
    }

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Stack(
                children: [
                  avatar,
                  if (selected)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accentColor.withValues(alpha: 0.7),
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      contact.displayName.isNotEmpty
                          ? contact.displayName
                          : contact.username.isNotEmpty
                              ? '@${contact.username}'
                              : contact.phone,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (contact.username.isNotEmpty ||
                        contact.isOnline) ...[
                      const SizedBox(height: 2),
                      Text(
                        contact.isOnline
                            ? 'online'
                            : '@${contact.username}',
                        style: TextStyle(
                          fontSize: 12,
                          color: contact.isOnline
                              ? const Color(0xFF4DC920)
                              : subtextColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _fallbackAvatar(ContactInfo c, bool isDark) {
    final name = c.displayName.isNotEmpty ? c.displayName : c.username;
    final idx = name.isNotEmpty ? name.codeUnitAt(0) % _userpicGradients.length : 0;
    final colors = _userpicGradients[idx];
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 21,
      backgroundColor: colors[0],
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _UserpicButton extends StatefulWidget {
  final double size;
  final List<Color> gradientColors;
  final String initials;
  final Uint8List? photoBytes;
  final bool isForum;
  final double uploadProgress;
  final void Function(Offset globalPosition) onTap;

  const _UserpicButton({
    required this.size,
    required this.gradientColors,
    required this.initials,
    this.photoBytes,
    this.isForum = false,
    this.uploadProgress = -1,
    required this.onTap,
  });

  @override
  State<_UserpicButton> createState() => _UserpicButtonState();
}

class _UserpicButtonState extends State<_UserpicButton>
    with SingleTickerProviderStateMixin {
  bool _hovering = false;
  late AnimationController _progressAnim;

  @override
  void initState() {
    super.initState();
    _progressAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    if (widget.uploadProgress >= 0) _progressAnim.repeat();
  }

  @override
  void didUpdateWidget(_UserpicButton old) {
    super.didUpdateWidget(old);
    if (widget.uploadProgress >= 0 && !_progressAnim.isAnimating) {
      _progressAnim.repeat();
    } else if (widget.uploadProgress < 0 && _progressAnim.isAnimating) {
      _progressAnim.stop();
    }
  }

  @override
  void dispose() {
    _progressAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.photoBytes != null;
    final forumRadius = widget.size * 0.32;
    final shape = widget.isForum
        ? BoxShape.rectangle
        : BoxShape.circle;
    final borderRadius = widget.isForum
        ? BorderRadius.circular(forumRadius)
        : null;
    final fontSize = (widget.size * 13 / 33).roundToDouble();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapUp: (details) => widget.onTap(details.globalPosition),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            children: [
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: shape,
                  borderRadius: borderRadius,
                  gradient: hasImage
                      ? null
                      : LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: widget.gradientColors,
                        ),
                  image: hasImage
                      ? DecorationImage(
                          image: MemoryImage(widget.photoBytes!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: !hasImage && widget.initials.isNotEmpty
                    ? Center(
                        child: Text(
                          widget.initials,
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : null,
              ),

              if (_hovering || !hasImage)
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: shape,
                    borderRadius: borderRadius,
                    color: _hovering
                        ? (hasImage
                            ? const Color(0x54000000)
                            : const Color(0x18000000))
                        : Colors.transparent,
                  ),
                ),

              if (!hasImage || _hovering)
                const Positioned(
                  left: 21,
                  top: 23,
                  child: Icon(
                    Icons.add_a_photo_outlined,
                    size: 24,
                    color: Color(0xE6FFFFFF),
                  ),
                ),

              if (widget.uploadProgress >= 0) ...[
                ClipPath(
                  clipper: _BottomClipper(
                    height: 24,
                    isForum: widget.isForum,
                    radius: forumRadius,
                  ),
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: shape,
                      borderRadius: borderRadius,
                      color: const Color(0x7F000000),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: AnimatedBuilder(
                      animation: _progressAnim,
                      builder: (ctx, _) {
                        return CustomPaint(
                          painter: _ProgressRingPainter(
                            progress: widget.uploadProgress,
                            rotation: _progressAnim.value * 2 * math.pi,
                            strokeWidth: 3,
                            isForum: widget.isForum,
                            forumRadius: forumRadius - 8,
                          ),
                        );
                      },
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

class _BottomClipper extends CustomClipper<Path> {
  final double height;
  final bool isForum;
  final double radius;

  _BottomClipper({
    required this.height,
    required this.isForum,
    required this.radius,
  });

  @override
  Path getClip(Size size) {
    final path = Path();
    if (isForum) {
      path.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Radius.circular(radius),
      ));
    } else {
      path.addOval(Rect.fromLTWH(0, 0, size.width, size.height));
    }
    final cutout = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height - height));
    return Path.combine(PathOperation.intersect, path, Path()
      ..addRect(Rect.fromLTWH(0, size.height - height, size.width, height)));
  }

  @override
  bool shouldReclip(_BottomClipper old) =>
      old.height != height || old.isForum != isForum || old.radius != radius;
}

class _ProgressRingPainter extends CustomPainter {
  final double progress;
  final double rotation;
  final double strokeWidth;
  final bool isForum;
  final double forumRadius;

  _ProgressRingPainter({
    required this.progress,
    required this.rotation,
    required this.strokeWidth,
    this.isForum = false,
    this.forumRadius = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final sweepAngle = progress.clamp(0.05, 1.0) * 2 * math.pi;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(rotation);
    canvas.translate(-size.width / 2, -size.height / 2);

    if (isForum) {
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(forumRadius));
      final path = Path()..addRRect(rrect);
      canvas.drawPath(path, paint..style = PaintingStyle.stroke);
    } else {
      canvas.drawArc(rect, -math.pi / 2, sweepAngle, false, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ProgressRingPainter old) =>
      old.progress != progress || old.rotation != rotation;
}
