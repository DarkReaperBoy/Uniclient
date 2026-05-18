import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/chat_state.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/telegram_palette.dart';
import 'choose_datetime_box.dart';
import 'create_group_wizard.dart' show showEditPeerTypeBox;
import 'info_panel.dart';
import 'telegram_toast.dart';

Future<bool?> showEditPeerInfoBox(
  BuildContext context, {
  required ChatInfo chat,
  List<MemberInfo>? members,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _EditPeerInfoBox(chat: chat, members: members),
  );
}

class _EditPeerInfoBox extends StatefulWidget {
  final ChatInfo chat;
  final List<MemberInfo>? members;

  const _EditPeerInfoBox({required this.chat, this.members});

  @override
  State<_EditPeerInfoBox> createState() => _EditPeerInfoBoxState();
}

class _EditPeerInfoBoxState extends State<_EditPeerInfoBox> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  bool _saving = false;
  String? _avatarPath;
  bool _avatarRemoved = false;
  bool _avatarIsVideo = false;
  bool _antispamEnabled = false;
  bool _antispamLoaded = false;
  bool _historyHidden = false;
  bool _historyLoaded = false;
  bool _canEditPreHistoryHidden = true;
  bool _signMessages = false;
  bool _signMessagesLoaded = false;
  bool _signProfiles = false;
  bool _autoTranslateDisabled = true;
  bool _autoTranslateLoaded = false;
  int _autoTranslateMinLevel = 0;
  bool _forumEnabled = false;
  String _linkedChatId = '';
  bool _hasPublicUsername = false;
  int _pendingRequestsCount = 0;
  int _boostLevel = 0;
  int _forumMinMembers = 200;
  bool _noForwards = false;
  bool _joinToSend = false;
  bool _joinRequest = false;
  bool _origNoForwards = false;
  bool _origJoinToSend = false;
  bool _origJoinRequest = false;

  bool get _isChannel => widget.chat.type == ChatType.channel;
  bool get _isBot => widget.chat.isBot;
  bool get _isMegagroup => !_isChannel && !_isBot && widget.chat.type == ChatType.group;

  static const int _antispamMinMembers = 100;

  String get _peerLabel {
    if (_isBot) return 'Bot';
    if (_isChannel) return 'Channel';
    return 'Group';
  }

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.chat.title);
    _descCtrl = TextEditingController();
    _forumEnabled = widget.chat.isForum;
    _loadDescription();
    if (_isMegagroup) _loadAntiSpamState();
    _loadChatFullInfo();
  }

  Future<void> _loadDescription() async {
    final engine = context.read<EngineService>();
    try {
      final fullInfo = await engine.getFullChatInfo(
        widget.chat.accountId,
        widget.chat.chatId,
      );
      if (mounted && fullInfo.isNotEmpty) {
        final about = fullInfo['about'] as String? ?? fullInfo['bio'] as String? ?? '';
        if (about.isNotEmpty) {
          setState(() => _descCtrl.text = about);
        }
      }
    } catch (_) {
      try {
        final profile = await engine.getUserProfile(
          widget.chat.accountId,
          widget.chat.chatId,
        );
        if (profile != null && mounted) {
          setState(() => _descCtrl.text = profile.bio);
        }
      } catch (_) {}
    }
  }

  Future<void> _loadChatFullInfo() async {
    final engine = context.read<EngineService>();
    try {
      final flags = await engine.getChatPermissionFlags(
        widget.chat.accountId,
        widget.chat.chatId,
      );
      if (mounted) {
        setState(() {
          _historyHidden = flags['pre_history_hidden'] == true;
          _historyLoaded = true;
          _canEditPreHistoryHidden = flags['can_edit_pre_history_hidden'] as bool? ?? true;
          _signMessages = flags['signatures'] == true;
          _signProfiles = flags['signature_profiles'] == true;
          _signMessagesLoaded = true;
          _autoTranslateDisabled = flags['no_translations'] == true;
          _autoTranslateLoaded = true;
          _autoTranslateMinLevel = (flags['auto_translate_min_level'] as int?) ?? 0;
          _linkedChatId = (flags['linked_chat_id'] as String?) ?? '';
          _hasPublicUsername = flags['has_username'] == true;
          _pendingRequestsCount = (flags['pending_requests_count'] as int?) ?? 0;
          _boostLevel = (flags['boost_level'] as int?) ?? 0;
          _forumMinMembers = (flags['forum_upgrade_participants_min'] as int?) ?? 200;
          _noForwards = flags['no_forwards'] == true;
          _joinToSend = flags['join_to_send'] == true;
          _joinRequest = flags['join_request'] == true;
          _origNoForwards = _noForwards;
          _origJoinToSend = _joinToSend;
          _origJoinRequest = _joinRequest;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _historyLoaded = true;
          _signMessagesLoaded = true;
          _autoTranslateLoaded = true;
        });
      }
    }
  }

  Future<void> _loadAntiSpamState() async {
    try {
      final engine = context.read<EngineService>();
      final flags = await engine.getChatPermissionFlags(
        widget.chat.accountId,
        widget.chat.chatId,
      );
      if (mounted) {
        setState(() {
          _antispamEnabled = flags['antispam'] == true;
          _antispamLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _antispamLoaded = true);
    }
  }

  Future<void> _toggleAntiSpam(bool value) async {
    final engine = context.read<EngineService>();
    setState(() => _antispamEnabled = value);
    try {
      await engine.toggleAntiSpam(
        widget.chat.accountId,
        widget.chat.chatId,
        value,
      );
    } catch (_) {
      if (mounted) setState(() => _antispamEnabled = !value);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = PaletteProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE0E0E0);
    final accentColor = palette.windowBgActive;
    final attentionColor = palette.attentionButtonFg;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: bgColor,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTitleBar(textColor, bgColor, accentColor, dividerColor),
            Flexible(
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  _buildPhotoSection(accentColor, textColor, subTextColor),
                  _buildTitleField(textColor),
                  _buildDescriptionField(textColor, subTextColor),
                  Divider(height: 1, color: dividerColor),
                  const SizedBox(height: 6),
                  _buildSettingsSection(textColor, subTextColor, accentColor),
                  Divider(height: 1, color: dividerColor),
                  const SizedBox(height: 6),
                  _buildAdminControlsSection(textColor, subTextColor),
                  if (_isMegagroup && _antispamLoaded) ...[
                    Divider(height: 1, color: dividerColor),
                    const SizedBox(height: 6),
                    _buildAntiSpamSection(textColor, subTextColor, accentColor),
                  ],
                  if (!_isChannel && !_isBot) ...[
                    Divider(height: 1, color: dividerColor),
                    const SizedBox(height: 6),
                    _buildStickerSection(textColor, subTextColor, accentColor),
                  ],
                  Divider(height: 1, color: dividerColor),
                  const SizedBox(height: 6),
                  _buildDeleteButton(attentionColor),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar(
    Color textColor,
    Color bgColor,
    Color accentColor,
    Color dividerColor,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 8, top: 4, bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Edit $_peerLabel',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                TextButton(
                  onPressed: _onSave,
                  child: Text(
                    'Save',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: accentColor,
                    ),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 14,
                    color: textColor.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: dividerColor),
      ],
    );
  }

  Widget _buildPhotoSection(Color accentColor, Color textColor, Color subTextColor) {
    final avatarPath = widget.chat.avatarPath;
    final hasAvatar = !_avatarRemoved &&
        (_avatarPath != null || (avatarPath.isNotEmpty && File(avatarPath).existsSync()));
    final displayPath = _avatarPath ?? avatarPath;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
      child: Row(
        children: [
          GestureDetector(
            onSecondaryTapDown: (d) => _showPhotoMenu(d.globalPosition),
            onLongPress: () => _showPhotoMenu(Offset.zero),
            child: CircleAvatar(
              radius: 40,
              backgroundColor: accentColor,
              backgroundImage:
                  hasAvatar && displayPath.isNotEmpty ? FileImage(File(displayPath)) : null,
              child: hasAvatar
                  ? null
                  : Text(
                      _initials(widget.chat.title),
                      style: const TextStyle(fontSize: 22, color: Colors.white),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.chat.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.chat.memberCount} ${_isChannel ? "subscribers" : "members"}',
                  style: TextStyle(fontSize: 13, color: subTextColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPhotoMenu(Offset position) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuPos = position == Offset.zero ? null : position;

    showMenu<String>(
      context: context,
      position: menuPos != null
          ? RelativeRect.fromLTRB(menuPos.dx, menuPos.dy, menuPos.dx, menuPos.dy)
          : const RelativeRect.fromLTRB(80, 120, 80, 120),
      items: [
        const PopupMenuItem(value: 'set', child: Text('Set Photo')),
        const PopupMenuItem(value: 'set_video', child: Text('Set Video')),
        const PopupMenuItem(value: 'remove', child: Text('Remove Photo')),
      ],
      color: isDark ? const Color(0xFF1E2C3A) : Colors.white,
    ).then((value) {
      if (value == 'set' && mounted) {
        _pickAndUploadPhoto();
      } else if (value == 'set_video' && mounted) {
        _pickAndUploadVideo();
      } else if (value == 'remove' && mounted) {
        _removePhoto();
      }
    });
  }

  Future<void> _pickAndUploadPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null || !mounted) return;
    setState(() {
      _avatarPath = path;
      _avatarRemoved = false;
      _avatarIsVideo = false;
    });
  }

  Future<void> _pickAndUploadVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null || !mounted) return;
    setState(() {
      _avatarPath = path;
      _avatarRemoved = false;
      _avatarIsVideo = true;
    });
  }

  Future<void> _removePhoto() async {
    setState(() {
      _avatarRemoved = true;
      _avatarPath = null;
      _avatarIsVideo = false;
    });
  }

  Widget _buildTitleField(Color textColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(27, 13, 22, 8),
      child: TextField(
        controller: _titleCtrl,
        maxLength: 128,
        autofocus: true,
        style: TextStyle(fontSize: 14, color: textColor),
        decoration: InputDecoration(
          labelText: '${_peerLabel} Name',
          counterText: '',
          isDense: true,
          border: const UnderlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildDescriptionField(Color textColor, Color subTextColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 3, 22, 2),
      child: TextField(
        controller: _descCtrl,
        maxLength: 255,
        maxLines: null,
        minLines: 2,
        style: TextStyle(fontSize: 14, color: textColor),
        decoration: InputDecoration(
          labelText: 'Description',
          counterText: '',
          isDense: true,
          hintText: 'Add a description...',
          hintStyle: TextStyle(color: subTextColor),
          border: const UnderlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildSettingsSection(Color textColor, Color subTextColor, Color accentColor) {
    final chat = widget.chat;
    final isPrivate = !chat.chatId.startsWith('-100');
    final showHistoryVis = !_isChannel
        && !_hasPublicUsername
        && !_forumEnabled
        && _linkedChatId.isEmpty
        && _canEditPreHistoryHidden;
    final topicsLocked = (!chat.isForum && chat.memberCount < _forumMinMembers)
        || _linkedChatId.isNotEmpty;

    return Column(
      children: [
        _EditRow(
          icon: Icons.lock_outline,
          label: _isChannel ? 'Channel Type' : 'Group Type',
          value: isPrivate ? 'Private' : 'Public',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () async {
            final changed = await showEditPeerTypeBox(
              context,
              accountId: chat.accountId,
              chatId: chat.chatId,
              isChannel: _isChannel,
            );
            if (changed == true && mounted) {
              _loadChatFullInfo();
            }
          },
        ),
        _EditRow(
          icon: _isChannel ? Icons.forum_outlined : Icons.groups_outlined,
          label: _isChannel ? 'Discussion Group' : 'Linked Channel',
          value: 'Add',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => _showLinkedChatDialog(),
        ),
        _EditRow(
          icon: Icons.palette_outlined,
          label: 'Color & Emoji',
          value: '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => _showColorPickerDialog(textColor, subTextColor, accentColor),
        ),
        if (!_isChannel) ...[
          if (showHistoryVis)
            _EditRow(
              icon: Icons.chat_bubble_outline,
              label: 'Visible History',
              value: _historyLoaded ? (_historyHidden ? 'Hidden' : 'Visible') : '...',
              textColor: textColor,
              subTextColor: subTextColor,
              onTap: () => _showHistoryVisibilityDialog(textColor, subTextColor, accentColor),
            ),
          if (chat.isForum || chat.memberCount > 0)
            _EditRow(
              icon: Icons.topic_outlined,
              label: 'Topics',
              value: _forumEnabled ? 'On' : 'Off',
              textColor: textColor,
              subTextColor: subTextColor,
              onTap: topicsLocked
                  ? () => showTelegramToast(context,
                      _linkedChatId.isNotEmpty
                          ? 'Cannot enable topics with a linked discussion group.'
                          : 'Group needs at least $_forumMinMembers members to enable topics.')
                  : () => _toggleTopics(),
            ),
        ],
        if (_isChannel) ...[
          _EditRow(
            icon: Icons.translate,
            label: 'Auto-Translation',
            value: '',
            textColor: textColor,
            subTextColor: subTextColor,
            isToggle: true,
            toggleValue: _autoTranslateLoaded ? !_autoTranslateDisabled : false,
            onTap: () => _toggleAutoTranslate(),
          ),
          _EditRow(
            icon: Icons.draw_outlined,
            label: 'Sign Messages',
            value: '',
            textColor: textColor,
            subTextColor: subTextColor,
            isToggle: true,
            toggleValue: _signMessagesLoaded ? _signMessages : false,
            onTap: () => _toggleSignMessages(),
          ),
          if (_signMessages)
            _EditRow(
              icon: Icons.person_outline,
              label: 'Sign Profiles',
              value: '',
              textColor: textColor,
              subTextColor: subTextColor,
              isToggle: true,
              toggleValue: _signProfiles,
              onTap: () => _toggleSignProfiles(),
            ),
          if (chat.type == ChatType.channel)
            _EditRow(
              icon: Icons.monetization_on_outlined,
              label: 'Direct Messages',
              value: '',
              textColor: textColor,
              subTextColor: subTextColor,
              onTap: () => _showDirectMessagesDialog(textColor, subTextColor, accentColor),
            ),
        ],
      ],
    );
  }

  Future<void> _showLinkedChatDialog() async {
    final engine = context.read<EngineService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final accentColor = PaletteProvider.of(context).windowBgActive;

    try {
      final linkedId = await engine.getLinkedChatId(
        widget.chat.accountId,
        widget.chat.chatId,
      );
      if (!mounted) return;

      List<Map<String, dynamic>> groups = [];
      if (_isChannel) {
        try {
          groups = await engine.getDiscussionGroups(widget.chat.accountId);
        } catch (_) {}
      }
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: bgColor,
            title: Text(
              _isChannel ? 'Discussion Group' : 'Linked Channel',
              style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600),
            ),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (linkedId.isNotEmpty) ...[
                    Text('Currently linked:', style: TextStyle(color: subTextColor, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(linkedId, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 12),
                  ] else
                    Text(
                      'No ${_isChannel ? "discussion group" : "channel"} linked.',
                      style: TextStyle(color: subTextColor, fontSize: 14),
                    ),
                  if (_isChannel && groups.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('Available groups:', style: TextStyle(color: subTextColor, fontSize: 13)),
                    const SizedBox(height: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: groups.length,
                        itemBuilder: (_, i) {
                          final g = groups[i];
                          final gId = g['id'] as String? ?? '';
                          final gTitle = g['title'] as String? ?? 'Untitled';
                          final isLinked = gId == linkedId;
                          return ListTile(
                            dense: true,
                            title: Text(gTitle, style: TextStyle(color: textColor, fontSize: 14)),
                            trailing: isLinked
                                ? Icon(Icons.check_circle, color: accentColor, size: 20)
                                : null,
                            onTap: () async {
                              Navigator.pop(ctx);
                              try {
                                await engine.setDiscussionGroup(
                                  widget.chat.accountId,
                                  widget.chat.chatId,
                                  gId,
                                );
                                if (mounted) showTelegramToast(context, 'Discussion group set to "$gTitle"');
                              } catch (e) {
                                if (mounted) showTelegramToast(context, 'Failed: $e');
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (linkedId.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await engine.setDiscussionGroup(
                        widget.chat.accountId,
                        _isChannel ? widget.chat.chatId : '',
                        _isChannel ? '' : widget.chat.chatId,
                      );
                      if (mounted) showTelegramToast(context, 'Discussion group unlinked');
                    } catch (e) {
                      if (mounted) showTelegramToast(context, 'Failed to unlink: $e');
                    }
                  },
                  child: Text('Unlink', style: TextStyle(color: Colors.red.shade400)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Close', style: TextStyle(color: subTextColor)),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (mounted) showTelegramToast(context, 'Failed to load: $e');
    }
  }

  void _showHistoryVisibilityDialog(Color textColor, Color subTextColor, Color accentColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text(
          'Chat History for New Members',
          style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Choose whether new members can see the entire message history.',
          style: TextStyle(color: subTextColor, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _setHistoryVisibility(true);
            },
            child: Text(
              'Hidden',
              style: TextStyle(color: _historyHidden ? accentColor : subTextColor),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _setHistoryVisibility(false);
            },
            child: Text(
              'Visible',
              style: TextStyle(color: !_historyHidden ? accentColor : subTextColor),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setHistoryVisibility(bool hidden) async {
    final engine = context.read<EngineService>();
    final prev = _historyHidden;
    setState(() => _historyHidden = hidden);
    try {
      await engine.togglePreHistoryHidden(
        widget.chat.accountId,
        widget.chat.chatId,
        hidden,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _historyHidden = prev);
        showTelegramToast(context, 'Failed: $e');
      }
    }
  }

  Future<void> _toggleTopics() async {
    final engine = context.read<EngineService>();
    final newVal = !_forumEnabled;
    setState(() => _forumEnabled = newVal);
    try {
      await engine.toggleForum(
        widget.chat.accountId,
        widget.chat.chatId,
        newVal,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _forumEnabled = !newVal);
        showTelegramToast(context, 'Failed: $e');
      }
    }
  }

  Future<void> _showBoostRequiredDialog(int currentLevel, int requiredLevel) async {
    final engine = context.read<EngineService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    final accentColor = PaletteProvider.of(context).windowBgActive;

    Map<String, dynamic>? boostData;
    try {
      boostData = await engine.getBoosts(widget.chat.accountId, widget.chat.chatId);
    } catch (_) {}
    if (!mounted) return;

    final boosts = boostData?['boosts'] as int? ?? 0;
    final currentLevelBoosts = boostData?['current_level_boosts'] as int? ?? 0;
    final nextLevelBoosts = boostData?['next_level_boosts'] as int? ?? 0;
    final boostUrl = boostData?['boost_url'] as String? ?? '';

    final progress = nextLevelBoosts > currentLevelBoosts
        ? (boosts - currentLevelBoosts) / (nextLevelBoosts - currentLevelBoosts)
        : 0.0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Column(
          children: [
            Icon(Icons.translate, size: 48, color: accentColor),
            const SizedBox(height: 12),
            Text('Enable Auto-Translation',
              textAlign: TextAlign.center,
              style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2b3945) : const Color(0xFFe9ecef),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Level $currentLevel',
                        style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                      if (nextLevelBoosts > 0)
                        Text('Level ${currentLevel + 1}',
                          style: TextStyle(color: subTextColor, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      backgroundColor: isDark ? const Color(0xFF1a2633) : const Color(0xFFd4d8dc),
                      valueColor: AlwaysStoppedAnimation(accentColor),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('$boosts / ${nextLevelBoosts > 0 ? nextLevelBoosts : '?'} boosts',
                    style: TextStyle(color: subTextColor, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Your channel needs to reach Level $requiredLevel to enable auto-translation.\n\n'
              'Ask your subscribers to boost your channel.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subTextColor, fontSize: 14),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          if (boostUrl.isNotEmpty)
            TextButton.icon(
              icon: Icon(Icons.copy, size: 16, color: accentColor),
              label: Text('Copy Boost Link', style: TextStyle(color: accentColor)),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: boostUrl));
                showTelegramToast(ctx, 'Boost link copied');
              },
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: TextStyle(color: subTextColor)),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleAutoTranslate() async {
    final minLevel = _autoTranslateMinLevel > 0 ? _autoTranslateMinLevel : 3;
    if (_autoTranslateDisabled && _boostLevel < minLevel) {
      _showBoostRequiredDialog(_boostLevel, minLevel);
      return;
    }
    final engine = context.read<EngineService>();
    final newVal = !_autoTranslateDisabled;
    setState(() => _autoTranslateDisabled = newVal);
    try {
      await engine.togglePeerTranslations(
        widget.chat.accountId,
        widget.chat.chatId,
        newVal,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _autoTranslateDisabled = !newVal);
        showTelegramToast(context, 'Failed: $e');
      }
    }
  }

  Future<void> _toggleSignMessages() async {
    final engine = context.read<EngineService>();
    final newVal = !_signMessages;
    setState(() {
      _signMessages = newVal;
      if (!newVal) _signProfiles = false;
    });
    try {
      await engine.toggleSignatures(
        widget.chat.accountId,
        widget.chat.chatId,
        newVal,
        profilesEnabled: newVal ? _signProfiles : false,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _signMessages = !newVal;
          if (!newVal) _signProfiles = false;
        });
        showTelegramToast(context, 'Failed: $e');
      }
    }
  }

  Future<void> _toggleSignProfiles() async {
    final engine = context.read<EngineService>();
    final newVal = !_signProfiles;
    setState(() => _signProfiles = newVal);
    try {
      await engine.toggleSignatures(
        widget.chat.accountId,
        widget.chat.chatId,
        _signMessages,
        profilesEnabled: newVal,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _signProfiles = !newVal);
        showTelegramToast(context, 'Failed: $e');
      }
    }
  }

  Future<void> _showReactionsDialog(Color textColor, Color subTextColor) async {
    final engine = context.read<EngineService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final accentColor = PaletteProvider.of(context).windowBgActive;

    List<String> availableReactions = [];
    try {
      availableReactions = await engine.getAvailableReactions(widget.chat.accountId);
    } catch (_) {}

    if (!mounted) return;

    String mode = 'all';
    final selectedEmojis = <String>{};

    final result = await showDialog<(String, List<String>)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: bgColor,
          title: Text('Reactions', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final opt in [('all', 'All Reactions'), ('some', 'Some Reactions'), ('none', 'No Reactions')])
                  RadioListTile<String>(
                    value: opt.$1,
                    groupValue: mode,
                    title: Text(opt.$2, style: TextStyle(color: textColor, fontSize: 14)),
                    activeColor: accentColor,
                    onChanged: (v) => setDialogState(() => mode = v!),
                    dense: true,
                  ),
                if (mode == 'some' && availableReactions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Select allowed reactions:',
                    style: TextStyle(color: subTextColor, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: availableReactions.map((emoji) {
                          final isSelected = selectedEmojis.contains(emoji);
                          return GestureDetector(
                            onTap: () => setDialogState(() {
                              if (isSelected) {
                                selectedEmojis.remove(emoji);
                              } else {
                                selectedEmojis.add(emoji);
                              }
                            }),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isSelected ? accentColor.withValues(alpha: 0.2) : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected ? accentColor : (isDark ? Colors.white24 : Colors.black12),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(emoji, style: const TextStyle(fontSize: 20)),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: subTextColor))),
            TextButton(
              onPressed: () {
                if (mode == 'some' && selectedEmojis.isEmpty) {
                  showTelegramToast(ctx, 'Select at least one reaction');
                  return;
                }
                Navigator.pop(ctx, (mode, selectedEmojis.toList()));
              },
              child: Text('Save', style: TextStyle(color: accentColor, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    try {
      await engine.setChatReactionsMode(
        widget.chat.accountId,
        widget.chat.chatId,
        result.$1,
        emojis: result.$2,
      );
      if (mounted) showTelegramToast(context, 'Reactions updated');
    } catch (e) {
      if (mounted) showTelegramToast(context, 'Failed: $e');
    }
  }

  Future<void> _showColorPickerDialog(Color textColor, Color subTextColor, Color accentColor) async {
    final engine = context.read<EngineService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;

    List<PeerColorEntry> colors = [];
    try {
      colors = await engine.getPeerColors(widget.chat.accountId);
    } catch (_) {}
    if (!mounted || colors.isEmpty) {
      if (mounted) showTelegramToast(context, 'Could not load colors');
      return;
    }

    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('Color & Emoji', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: 300,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: colors.map((c) {
              final color = c.dayColors.isNotEmpty
                  ? Color(0xFF000000 | c.dayColors.first)
                  : const Color(0xFF999999);
              return GestureDetector(
                onTap: () => Navigator.pop(ctx, c.colorId),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: subTextColor))),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    try {
      await engine.updateChannelColor(widget.chat.accountId, widget.chat.chatId, selected);
      if (mounted) showTelegramToast(context, 'Color updated');
    } catch (e) {
      if (mounted) showTelegramToast(context, 'Failed: $e');
    }
  }

  Future<void> _showDirectMessagesDialog(Color textColor, Color subTextColor, Color accentColor) async {
    final engine = context.read<EngineService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    int starsPrice = widget.chat.starsToSend;
    final priceCtrl = TextEditingController(text: starsPrice > 0 ? '$starsPrice' : '');

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('Direct Messages', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set a price in Telegram Stars for users to send direct messages to this channel.',
              style: TextStyle(color: subTextColor, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              style: TextStyle(color: textColor, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Stars per message (0 = free)',
                hintText: '0',
                hintStyle: TextStyle(color: subTextColor),
                border: const UnderlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: subTextColor))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(priceCtrl.text) ?? 0),
            child: Text('Save', style: TextStyle(color: accentColor, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    try {
      await engine.updatePaidMessagesPrice(
        widget.chat.accountId,
        widget.chat.chatId,
        result,
        broadcastEnabled: result >= 0,
      );
      if (mounted) showTelegramToast(context, 'Direct messages price updated');
    } catch (e) {
      if (mounted) showTelegramToast(context, 'Failed: $e');
    }
  }

  Widget _buildBotManageSection(Color textColor, Color subTextColor) {
    final engine = context.read<EngineService>();
    return Column(
      children: [
        if (_hasPublicUsername)
          _EditRow(
            icon: Icons.link,
            label: 'Public Links',
            value: '',
            textColor: textColor,
            subTextColor: subTextColor,
            onTap: () async {
              try {
                final username = await engine.getChatUsername(widget.chat.accountId, widget.chat.chatId);
                if (mounted && username.isNotEmpty) {
                  showTelegramToast(context, 'Bot link: t.me/$username');
                }
              } catch (e) {
                if (mounted) showTelegramToast(context, 'Failed: $e');
              }
            },
          ),
        _EditRow(
          icon: Icons.monetization_on_outlined,
          label: 'Currency Balance',
          value: '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => _showRevenueStats(textColor, subTextColor, isCurrency: true),
        ),
        _EditRow(
          icon: Icons.stars_outlined,
          label: 'Credits Balance',
          value: '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => _showRevenueStats(textColor, subTextColor, isCurrency: false),
        ),
        _EditRow(
          icon: Icons.handshake_outlined,
          label: 'Affiliate Program',
          value: '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => _showAffiliateProgramDialog(textColor, subTextColor),
        ),
        _EditRow(
          icon: Icons.info_outline,
          label: 'Edit Intro',
          value: '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => _openBotFather('${widget.chat.username}-intro'),
        ),
        _EditRow(
          icon: Icons.code,
          label: 'Edit Commands',
          value: '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => _openBotFather('${widget.chat.username}-commands'),
        ),
        _EditRow(
          icon: Icons.settings_outlined,
          label: 'Edit Settings',
          value: '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => _openBotFather(widget.chat.username),
        ),
        _EditRow(
          icon: Icons.verified_outlined,
          label: 'Verify Accounts',
          value: '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => _showVerifyAccountsDialog(textColor, subTextColor),
        ),
      ],
    );
  }

  Future<void> _openBotFather(String startParam) async {
    final engine = context.read<EngineService>();
    final accountId = widget.chat.accountId;
    try {
      final botFatherId = await engine.resolveUsername(accountId, 'BotFather');
      if (botFatherId == null || botFatherId.isEmpty) {
        if (mounted) showTelegramToast(context, 'Could not resolve @BotFather');
        return;
      }
      await engine.startBot(accountId, botFatherId, botFatherId, startParam);
      if (!mounted) return;
      final chatState = context.read<ChatState>();
      chatState.openChatById(botFatherId);
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) showTelegramToast(context, 'Failed: $e');
    }
  }

  Future<void> _showRevenueStats(Color textColor, Color subTextColor, {required bool isCurrency}) async {
    final engine = context.read<EngineService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final accentColor = PaletteProvider.of(context).windowBgActive;

    final stats = await engine.getStarsRevenueStats(
      widget.chat.accountId,
      widget.chat.chatId,
    );
    if (!mounted) return;
    if (stats == null) {
      showTelegramToast(context, 'Could not load revenue stats');
      return;
    }

    final currentBalance = stats['current_balance'] as int? ?? 0;
    final availableBalance = stats['available_balance'] as int? ?? 0;
    final overallRevenue = stats['overall_revenue'] as int? ?? 0;
    final withdrawalEnabled = stats['withdrawal_enabled'] as bool? ?? false;
    final usdRate = stats['usd_rate'] as double? ?? 0.0;

    String formatAmount(int stars) {
      if (isCurrency && usdRate > 0) {
        final usd = stars * usdRate / 1000;
        return '${stars.toString()} ≈ \$${usd.toStringAsFixed(2)}';
      }
      return '$stars Stars';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text(
          isCurrency ? 'Currency Balance' : 'Stars Balance',
          style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RevenueRow(label: 'Available Balance', value: formatAmount(availableBalance), textColor: textColor, subTextColor: subTextColor),
            const SizedBox(height: 8),
            _RevenueRow(label: 'Current Balance', value: formatAmount(currentBalance), textColor: textColor, subTextColor: subTextColor),
            const SizedBox(height: 8),
            _RevenueRow(label: 'Overall Revenue', value: formatAmount(overallRevenue), textColor: textColor, subTextColor: subTextColor),
            if (withdrawalEnabled) ...[
              const SizedBox(height: 12),
              Text('Withdrawal available', style: TextStyle(color: accentColor, fontSize: 13)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: TextStyle(color: subTextColor)),
          ),
        ],
      ),
    );
  }

  Future<void> _showAffiliateProgramDialog(Color textColor, Color subTextColor) async {
    final engine = context.read<EngineService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final accentColor = PaletteProvider.of(context).windowBgActive;

    Map<String, dynamic> affiliateInfo = {};
    try {
      final fullInfo = await engine.getFullChatInfo(
        widget.chat.accountId,
        widget.chat.chatId,
      );
      affiliateInfo = fullInfo['star_ref_program'] as Map<String, dynamic>? ?? {};
    } catch (_) {}
    if (!mounted) return;

    final hasProgram = affiliateInfo.isNotEmpty;
    final commission = affiliateInfo['commission_permille'] as int? ?? 0;
    final duration = affiliateInfo['duration_months'] as int? ?? 0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('Affiliate Program', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasProgram) ...[
              Text('Commission: ${(commission / 10).toStringAsFixed(1)}%',
                style: TextStyle(color: textColor, fontSize: 14)),
              if (duration > 0)
                Text('Duration: $duration months',
                  style: TextStyle(color: textColor, fontSize: 14)),
              if (duration == 0)
                Text('Duration: Lifetime',
                  style: TextStyle(color: textColor, fontSize: 14)),
            ] else
              Text('No affiliate program configured.',
                style: TextStyle(color: subTextColor, fontSize: 14)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: TextStyle(color: subTextColor)),
          ),
        ],
      ),
    );
  }

  Future<void> _showVerifyAccountsDialog(Color textColor, Color subTextColor) async {
    final engine = context.read<EngineService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final accentColor = PaletteProvider.of(context).windowBgActive;

    List<ContactInfo> contacts = [];
    try {
      contacts = await engine.getContacts(widget.chat.accountId);
    } catch (_) {}
    if (!mounted) return;

    final searchCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        var filtered = List<ContactInfo>.from(contacts);
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: bgColor,
            title: Text('Verify Accounts', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),
            content: SizedBox(
              width: 320,
              height: 400,
              child: Column(
                children: [
                  Text(
                    'Select accounts to grant or revoke custom verification badge from this bot.',
                    style: TextStyle(color: subTextColor, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchCtrl,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Search users...',
                      hintStyle: TextStyle(color: subTextColor.withValues(alpha: 0.5)),
                      prefixIcon: Icon(Icons.search, color: subTextColor),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (q) {
                      setDialogState(() {
                        final ql = q.toLowerCase();
                        filtered = contacts.where((c) =>
                          c.displayName.toLowerCase().contains(ql) ||
                          c.username.toLowerCase().contains(ql)
                        ).toList();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(child: Text('No contacts found', style: TextStyle(color: subTextColor)))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) {
                              final c = filtered[i];
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  c.isVerified ? Icons.verified : Icons.person_outline,
                                  color: c.isVerified ? accentColor : subTextColor,
                                  size: 20,
                                ),
                                title: Text(
                                  c.displayName.isNotEmpty ? c.displayName : c.username.isNotEmpty ? '@${c.username}' : c.userId,
                                  style: TextStyle(color: textColor, fontSize: 14),
                                ),
                                subtitle: c.username.isNotEmpty
                                    ? Text('@${c.username}', style: TextStyle(color: subTextColor, fontSize: 12))
                                    : null,
                                onTap: () async {
                                  try {
                                    await engine.callGeneric(
                                      widget.chat.accountId,
                                      'BotsSetCustomVerification',
                                      {
                                        'bot_id': widget.chat.chatId,
                                        'peer_id': c.userId,
                                        'enabled': !c.isVerified,
                                      },
                                    );
                                    if (ctx.mounted) {
                                      showTelegramToast(ctx, c.isVerified ? 'Verification removed' : 'Verification added');
                                    }
                                  } catch (e) {
                                    if (ctx.mounted) showTelegramToast(ctx, 'Failed: $e');
                                  }
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Close', style: TextStyle(color: subTextColor)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAdminControlsSection(Color textColor, Color subTextColor) {
    final memberCount = widget.chat.memberCount;
    final adminCount =
        widget.members?.where((m) => m.role == 'admin' || m.role == 'creator' || m.role == 'owner').length ?? 0;

    if (_isBot) {
      return _buildBotManageSection(textColor, subTextColor);
    }

    return Column(
      children: [
        _EditRow(
          icon: Icons.emoji_emotions_outlined,
          label: 'Reactions',
          value: '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => _showReactionsDialog(textColor, subTextColor),
        ),
        _EditRow(
          icon: Icons.security,
          label: 'Permissions',
          value: '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => showEditPeerPermissionsBox(
            context,
            accountId: widget.chat.accountId,
            chatId: widget.chat.chatId,
            isChannel: _isChannel,
            isForum: widget.chat.isForum,
            memberCount: widget.chat.memberCount,
          ),
        ),
        _EditRow(
          icon: Icons.link,
          label: 'Invite Links',
          value: '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => _showInviteLink(),
        ),
        if (_isChannel)
          _EditRow(
            icon: Icons.handshake_outlined,
            label: 'Affiliate Program',
            value: '',
            textColor: textColor,
            subTextColor: subTextColor,
            onTap: () => _showAffiliateProgramDialog(textColor, subTextColor),
          ),
        _EditRow(
          icon: Icons.admin_panel_settings_outlined,
          label: 'Administrators',
          value: adminCount > 0 ? '$adminCount' : '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => showMemberListScreen(
            context,
            accountId: widget.chat.accountId,
            chatId: widget.chat.chatId,
            isChannel: _isChannel,
            initialTab: _MemberTab.admins,
          ),
        ),
        _EditRow(
          icon: Icons.people_outline,
          label: _isChannel ? 'Subscribers' : 'Members',
          value: memberCount > 0 ? _formatCount(memberCount) : '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => showMemberListScreen(
            context,
            accountId: widget.chat.accountId,
            chatId: widget.chat.chatId,
            isChannel: _isChannel,
            initialTab: _MemberTab.members,
          ),
        ),
        _EditRow(
          icon: Icons.person_remove_outlined,
          label: 'Removed Users',
          value: '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => showMemberListScreen(
            context,
            accountId: widget.chat.accountId,
            chatId: widget.chat.chatId,
            isChannel: _isChannel,
            initialTab: _MemberTab.kicked,
          ),
        ),
        if (_pendingRequestsCount > 0)
          _EditRow(
            icon: Icons.person_add_outlined,
            label: 'Pending Requests',
            value: '$_pendingRequestsCount',
            textColor: textColor,
            subTextColor: subTextColor,
            onTap: () => showMemberListScreen(
              context,
              accountId: widget.chat.accountId,
              chatId: widget.chat.chatId,
              isChannel: _isChannel,
              initialTab: _MemberTab.requests,
            ),
          ),
        _EditRow(
          icon: Icons.history,
          label: 'Recent Actions',
          value: '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => showAdminLogScreen(
            context,
            accountId: widget.chat.accountId,
            chatId: widget.chat.chatId,
            chatTitle: widget.chat.title,
            chatAvatarPath: widget.chat.avatarPath,
            isChannel: _isChannel,
          ),
        ),
      ],
    );
  }

  Widget _buildAntiSpamSection(Color textColor, Color subTextColor, Color accentColor) {
    final memberCount = widget.chat.memberCount;
    final belowThreshold = memberCount < _antispamMinMembers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 21, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.smart_toy_outlined, size: 24, color: belowThreshold ? subTextColor : textColor),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Aggressive Anti-Spam',
                  style: TextStyle(
                    fontSize: 15,
                    color: belowThreshold ? subTextColor : textColor,
                  ),
                ),
              ),
              Switch(
                value: _antispamEnabled,
                onChanged: belowThreshold ? null : _toggleAntiSpam,
                activeColor: accentColor,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: Text(
            belowThreshold
                ? 'Aggressive Anti-Spam is available for groups with more than $_antispamMinMembers members.'
                : 'Telegram will filter more types of spam in this group.',
            style: TextStyle(fontSize: 12, color: subTextColor),
          ),
        ),
      ],
    );
  }

  Widget _buildStickerSection(Color textColor, Color subTextColor, Color accentColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(21, 6, 20, 4),
          child: Text(
            'Group Stickers',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: accentColor,
            ),
          ),
        ),
        _EditRow(
          icon: Icons.emoji_emotions_outlined,
          label: 'Add Stickers',
          value: '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => _showStickerSetPicker(textColor, subTextColor),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(21, 0, 20, 6),
          child: Text(
            'Choose a sticker set for your group.',
            style: TextStyle(fontSize: 12, color: subTextColor),
          ),
        ),
      ],
    );
  }

  void _showStickerSetPicker(Color textColor, Color subTextColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final accentColor = PaletteProvider.of(context).windowBgActive;
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text(
          'Group Sticker Set',
          style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: textColor, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Enter sticker set link or short name',
            hintStyle: TextStyle(color: subTextColor),
            border: const UnderlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: subTextColor)),
          ),
          TextButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final shortName = name
                  .replaceAll(RegExp(r'https?://t\.me/addstickers/'), '')
                  .replaceAll(RegExp(r'https?://telegram\.me/addstickers/'), '')
                  .trim();
              if (shortName.isEmpty) return;
              final engine = context.read<EngineService>();
              try {
                await engine.setGroupStickerSet(
                  widget.chat.accountId,
                  widget.chat.chatId,
                  shortName,
                );
                if (mounted) showTelegramToast(context, 'Sticker set applied');
              } catch (e) {
                if (mounted) showTelegramToast(context, 'Failed to set sticker set: $e');
              }
            },
            child: Text('Add', style: TextStyle(color: accentColor, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteButton(Color attentionColor) {
    return InkWell(
      onTap: _confirmDelete,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 21, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.delete_outline, size: 24, color: attentionColor),
            const SizedBox(width: 16),
            Text(
              'Delete $_peerLabel',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: attentionColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onSave() async {
    if (_saving) return;
    final newTitle = _titleCtrl.text.trim();
    if (newTitle.isEmpty) return;

    setState(() => _saving = true);
    final engine = context.read<EngineService>();
    try {
      if (newTitle != widget.chat.title) {
        await engine.editChatTitle(
          widget.chat.accountId,
          widget.chat.chatId,
          newTitle,
        );
      }
      final newDesc = _descCtrl.text.trim();
      await engine.editChatDescription(
        widget.chat.accountId,
        widget.chat.chatId,
        newDesc,
      );
      if (_avatarRemoved) {
        await engine.deleteChannelPhoto(
          widget.chat.accountId,
          widget.chat.chatId,
        );
      } else if (_avatarPath != null) {
        await engine.editChannelPhoto(
          widget.chat.accountId,
          widget.chat.chatId,
          _avatarPath!,
          isVideo: _avatarIsVideo,
        );
      }
      if (_noForwards != _origNoForwards) {
        await engine.toggleNoForwards(
          widget.chat.accountId,
          widget.chat.chatId,
          _noForwards,
        );
      }
      if (_joinToSend != _origJoinToSend) {
        await engine.toggleJoinToSend(
          widget.chat.accountId,
          widget.chat.chatId,
          _joinToSend,
        );
      }
      if (_joinRequest != _origJoinRequest) {
        await engine.toggleJoinRequest(
          widget.chat.accountId,
          widget.chat.chatId,
          _joinRequest,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showTelegramToast(context, 'Failed to save: $e');
      }
    }
  }

  void _confirmDelete() {
    final attentionColor = PaletteProvider.of(context).attentionButtonFg;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $_peerLabel'),
        content: Text(
          'Are you sure you want to delete "${widget.chat.title}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: attentionColor),
            onPressed: () {
              final engine = context.read<EngineService>();
              engine.deleteChat(widget.chat.accountId, widget.chat.chatId);
              Navigator.pop(ctx);
              Navigator.pop(context, true);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _showInviteLink() async {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => _InviteLinksBox(
        accountId: widget.chat.accountId,
        chatId: widget.chat.chatId,
        isChannel: _isChannel,
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '$count';
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

Future<void> showEditPeerPermissionsBox(
  BuildContext context, {
  required String accountId,
  required String chatId,
  required bool isChannel,
  required bool isForum,
  required int memberCount,
}) {
  return showDialog(
    context: context,
    builder: (ctx) => _EditPeerPermissionsBox(
      accountId: accountId,
      chatId: chatId,
      isChannel: isChannel,
      isForum: isForum,
      memberCount: memberCount,
    ),
  );
}

class _PermFlag {
  final String key;
  final String label;
  bool banned;

  _PermFlag({required this.key, required this.label, this.banned = false});
}

class _EditPeerPermissionsBox extends StatefulWidget {
  final String accountId;
  final String chatId;
  final bool isChannel;
  final bool isForum;
  final int memberCount;

  const _EditPeerPermissionsBox({
    required this.accountId,
    required this.chatId,
    required this.isChannel,
    required this.isForum,
    required this.memberCount,
  });

  @override
  State<_EditPeerPermissionsBox> createState() => _EditPeerPermissionsBoxState();
}

class _EditPeerPermissionsBoxState extends State<_EditPeerPermissionsBox>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _saving = false;
  bool _mediaExpanded = false;
  int _slowmodeIndex = 0;
  int _boostsUnrestrict = 0;
  int _chargeStars = 0;
  String? _error;

  late AnimationController _expandCtrl;
  late Animation<double> _expandAnim;

  static const _slowmodeValues = [0, 5, 10, 30, 60, 300, 900, 3600];
  static const _slowmodeLabels = ['Off', '5s', '10s', '30s', '1m', '5m', '15m', '1h'];
  static const _boostsValues = [0, 1, 2, 3, 4, 5];
  static const _boostsLabels = ['Off', '1', '2', '3', '4', '5'];
  static const _kDefaultChargeStars = 10;

  late final _PermFlag _sendPlain;
  late final List<_PermFlag> _mediaFlags;
  late final List<_PermFlag> _otherFlags;

  List<_PermFlag> get _allFlags => [_sendPlain, ..._mediaFlags, ..._otherFlags];

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _expandAnim = CurvedAnimation(parent: _expandCtrl, curve: Curves.easeOutCubic);
    _sendPlain = _PermFlag(key: 'send_plain', label: 'Send text messages');
    _mediaFlags = [
      _PermFlag(key: 'send_photos', label: 'Send photos'),
      _PermFlag(key: 'send_videos', label: 'Send videos'),
      _PermFlag(key: 'send_roundvideos', label: 'Send video messages'),
      _PermFlag(key: 'send_audios', label: 'Send music'),
      _PermFlag(key: 'send_voices', label: 'Send voice messages'),
      _PermFlag(key: 'send_docs', label: 'Send files'),
      _PermFlag(key: 'send_stickers', label: 'Send stickers & GIFs'),
      _PermFlag(key: 'embed_links', label: 'Send links'),
      _PermFlag(key: 'send_polls', label: 'Send polls'),
    ];
    _otherFlags = [
      _PermFlag(key: 'invite_users', label: 'Add members'),
      if (widget.isForum) _PermFlag(key: 'manage_topics', label: 'Create topics'),
      _PermFlag(key: 'pin_messages', label: 'Pin messages'),
      _PermFlag(key: 'edit_rank', label: 'Edit rank'),
      _PermFlag(key: 'change_info', label: 'Change group info'),
    ];
    _loadRights();
  }

  @override
  void dispose() {
    _expandCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRights() async {
    try {
      final engine = context.read<EngineService>();
      final rights = await engine.getDefaultBannedRights(widget.accountId, widget.chatId);
      if (!mounted) return;
      setState(() {
        for (final f in _allFlags) {
          f.banned = rights[f.key] == true;
        }
        final secs = rights['slowmode_seconds'] as int? ?? 0;
        _slowmodeIndex = _slowmodeValues.indexOf(secs);
        if (_slowmodeIndex < 0) _slowmodeIndex = 0;
        final boosts = rights['boosts_unrestrict'] as int? ?? 0;
        _boostsUnrestrict = boosts.clamp(0, 5);
        _chargeStars = (rights['charge_stars'] as int?) ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _onSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final engine = context.read<EngineService>();
      final rights = <String, dynamic>{};
      for (final f in _allFlags) {
        rights[f.key] = f.banned;
      }
      rights['slowmode_seconds'] = _slowmodeValues[_slowmodeIndex];
      await engine.setDefaultBannedRights(widget.accountId, widget.chatId, rights);
      await engine.setSlowMode(widget.accountId, widget.chatId, _slowmodeValues[_slowmodeIndex]);
      await engine.setBoostsUnrestrict(widget.accountId, widget.chatId, _boostsUnrestrict);
      await engine.updatePaidMessagesPrice(
        widget.accountId, widget.chatId, _chargeStars,
        broadcastEnabled: widget.isChannel && _chargeStars > 0,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showTelegramToast(context, 'Failed: $e');
      }
    }
  }

  void _toggleFlag(_PermFlag flag) {
    setState(() {
      flag.banned = !flag.banned;
      if (flag.key == 'send_plain' && flag.banned) {
        final embedLinks = _mediaFlags.firstWhere((f) => f.key == 'embed_links');
        embedLinks.banned = true;
      }
      if (flag.key == 'embed_links' && !flag.banned) {
        _sendPlain.banned = false;
      }
    });
  }

  int get _mediaAllowedCount => _mediaFlags.where((f) => !f.banned).length;

  @override
  Widget build(BuildContext context) {
    final palette = PaletteProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE0E0E0);
    final accentColor = palette.windowBgActive;
    final attentionColor = palette.attentionButtonFg;
    final headerColor = palette.windowActiveTextFg;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: bgColor,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTitleBar(textColor, bgColor, accentColor, dividerColor),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_error!, style: TextStyle(color: attentionColor)),
              )
            else
              Flexible(
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    const SizedBox(height: 8),
                    _buildSectionHeader('What can members of this group do?', headerColor),
                    const SizedBox(height: 4),
                    _buildPermToggle(_sendPlain, accentColor, attentionColor, textColor),
                    _buildMediaSection(accentColor, attentionColor, textColor, subTextColor),
                    for (final f in _otherFlags)
                      _buildPermToggle(f, accentColor, attentionColor, textColor),
                    Divider(height: 1, color: dividerColor),
                    const SizedBox(height: 12),
                    _buildSectionHeader('Slow Mode', headerColor),
                    const SizedBox(height: 4),
                    _buildSlowmodeSlider(accentColor, textColor, subTextColor),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
                      child: Text(
                        _slowmodeIndex == 0
                            ? 'Members can send messages without any restrictions.'
                            : 'Members will be able to send only one message every ${_slowmodeLabels[_slowmodeIndex]}.',
                        style: TextStyle(fontSize: 12, color: subTextColor),
                      ),
                    ),
                    Divider(height: 1, color: dividerColor),
                    const SizedBox(height: 12),
                    _buildSectionHeader('Boosts to Unrestrict', headerColor),
                    const SizedBox(height: 4),
                    _buildBoostsSlider(accentColor, textColor, subTextColor),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
                      child: Text(
                        _boostsUnrestrict == 0
                            ? 'No boosts required to bypass restrictions.'
                            : 'Users with $_boostsUnrestrict or more boosts can bypass restrictions.',
                        style: TextStyle(fontSize: 12, color: subTextColor),
                      ),
                    ),
                    Divider(height: 1, color: dividerColor),
                    const SizedBox(height: 12),
                    _buildSectionHeader('Charge Stars', headerColor),
                    const SizedBox(height: 4),
                    _buildChargeStarsSection(accentColor, textColor, subTextColor),
                    Divider(height: 1, color: dividerColor),
                    const SizedBox(height: 12),
                    _buildAddExceptionButton(accentColor, textColor),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar(Color textColor, Color bgColor, Color accentColor, Color dividerColor) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 8, top: 4, bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Permissions',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
                ),
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                TextButton(
                  onPressed: _onSave,
                  child: Text('Save', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accentColor)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(fontSize: 14, color: textColor.withValues(alpha: 0.6))),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: dividerColor),
      ],
    );
  }

  Widget _buildSectionHeader(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _buildPermToggle(_PermFlag flag, Color accentColor, Color attentionColor, Color textColor) {
    final allowed = !flag.banned;
    final isLocked = flag.key == 'embed_links' && _sendPlain.banned;

    return InkWell(
      onTap: () {
        if (isLocked) {
          showTelegramToast(context, '"Send links" requires "Send text messages" to be allowed.');
          return;
        }
        _toggleFlag(flag);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        child: Row(
          children: [
            if (isLocked)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.lock, size: 18, color: accentColor),
              ),
            Expanded(
              child: Text(
                flag.label,
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
            const SizedBox(width: 20),
            SizedBox(
              height: 24,
              child: Switch(
                value: allowed,
                onChanged: isLocked ? null : (_) => _toggleFlag(flag),
                activeColor: accentColor,
                inactiveThumbColor: attentionColor,
                inactiveTrackColor: attentionColor.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaSection(Color accentColor, Color attentionColor, Color textColor, Color subTextColor) {
    final allowedCount = _mediaAllowedCount;
    final total = _mediaFlags.length;

    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() => _mediaExpanded = !_mediaExpanded);
            if (_mediaExpanded) {
              _expandCtrl.forward();
            } else {
              _expandCtrl.reverse();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _expandAnim,
                  builder: (_, child) => Transform.rotate(
                    angle: _expandAnim.value * 3.14159,
                    child: child,
                  ),
                  child: Icon(Icons.expand_more, size: 20, color: textColor.withValues(alpha: 0.6)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Send media',
                    style: TextStyle(fontSize: 14, color: textColor),
                  ),
                ),
                Text(
                  '($allowedCount/$total)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: subTextColor),
                ),
                const SizedBox(width: 20),
                SizedBox(
                  height: 24,
                  child: Switch(
                    value: allowedCount == total,
                    onChanged: (val) {
                      setState(() {
                        for (final f in _mediaFlags) {
                          f.banned = !val;
                        }
                      });
                    },
                    activeColor: accentColor,
                    inactiveThumbColor: allowedCount == 0 ? attentionColor : accentColor,
                    inactiveTrackColor: allowedCount == 0
                        ? attentionColor.withValues(alpha: 0.3)
                        : accentColor.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizeTransition(
          sizeFactor: _expandAnim,
          child: Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Column(
              children: [
                for (final f in _mediaFlags)
                  _buildMediaCheckbox(f, accentColor, attentionColor, textColor),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaCheckbox(_PermFlag flag, Color accentColor, Color attentionColor, Color textColor) {
    final allowed = !flag.banned;
    return InkWell(
      onTap: () => _toggleFlag(flag),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: allowed,
                onChanged: (_) => _toggleFlag(flag),
                activeColor: accentColor,
                side: BorderSide(color: allowed ? accentColor : attentionColor, width: 2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(flag.label, style: TextStyle(fontSize: 14, color: textColor)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlowmodeSlider(Color accentColor, Color textColor, Color subTextColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(
        children: [
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accentColor,
              inactiveTrackColor: accentColor.withValues(alpha: 0.3),
              thumbColor: accentColor,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5),
              trackHeight: 3,
            ),
            child: Slider(
              value: _slowmodeIndex.toDouble(),
              min: 0,
              max: (_slowmodeValues.length - 1).toDouble(),
              divisions: _slowmodeValues.length - 1,
              onChanged: (v) => setState(() => _slowmodeIndex = v.round()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (int i = 0; i < _slowmodeLabels.length; i++)
                  Text(
                    _slowmodeLabels[i],
                    style: TextStyle(
                      fontSize: 10,
                      color: i == _slowmodeIndex ? textColor : subTextColor,
                      fontWeight: i == _slowmodeIndex ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoostsSlider(Color accentColor, Color textColor, Color subTextColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(
        children: [
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accentColor,
              inactiveTrackColor: accentColor.withValues(alpha: 0.3),
              thumbColor: accentColor,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5),
              trackHeight: 3,
            ),
            child: Slider(
              value: _boostsUnrestrict.toDouble(),
              min: 0,
              max: 5,
              divisions: 5,
              onChanged: (v) => setState(() => _boostsUnrestrict = v.round()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (int i = 0; i < _boostsLabels.length; i++)
                  Text(
                    _boostsLabels[i],
                    style: TextStyle(
                      fontSize: 10,
                      color: i == _boostsUnrestrict ? textColor : subTextColor,
                      fontWeight: i == _boostsUnrestrict ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChargeStarsSection(Color accentColor, Color textColor, Color subTextColor) {
    return Column(
      children: [
        InkWell(
          onTap: () {
            if (_chargeStars == 0) {
              setState(() => _chargeStars = _kDefaultChargeStars);
            } else {
              setState(() => _chargeStars = 0);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Charge Stars for Messages',
                    style: TextStyle(fontSize: 14, color: textColor),
                  ),
                ),
                const SizedBox(width: 20),
                SizedBox(
                  height: 24,
                  child: Switch(
                    value: _chargeStars > 0,
                    onChanged: (val) => setState(() =>
                      _chargeStars = val ? _kDefaultChargeStars : 0),
                    activeColor: accentColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_chargeStars > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
            child: Row(
              children: [
                Icon(Icons.star, size: 18, color: const Color(0xFFFFB800)),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: TextEditingController(text: '$_chargeStars'),
                      keyboardType: TextInputType.number,
                      style: TextStyle(fontSize: 14, color: textColor),
                      decoration: InputDecoration(
                        hintText: 'Stars per message',
                        hintStyle: TextStyle(color: subTextColor),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: accentColor),
                        ),
                      ),
                      onChanged: (v) {
                        final parsed = int.tryParse(v);
                        if (parsed != null && parsed >= 0) {
                          _chargeStars = parsed;
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: Text(
            _chargeStars > 0
                ? 'Non-admin members must pay $_chargeStars stars to send a message.'
                : 'Enable to charge stars for messages in this channel.',
            style: TextStyle(fontSize: 12, color: subTextColor),
          ),
        ),
      ],
    );
  }

  Widget _buildAddExceptionButton(Color accentColor, Color textColor) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        showMemberListScreen(
          context,
          accountId: widget.accountId,
          chatId: widget.chatId,
          isChannel: widget.isChannel,
          initialTab: _MemberTab.restricted,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.person_add_outlined, size: 24, color: accentColor),
            const SizedBox(width: 16),
            Text(
              'Add Exception',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accentColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color textColor;
  final Color subTextColor;
  final bool isToggle;
  final bool? toggleValue;
  final VoidCallback onTap;

  const _EditRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.textColor,
    required this.subTextColor,
    this.isToggle = false,
    this.toggleValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 21, top: 11, right: 20, bottom: 9),
        child: Row(
          children: [
            Icon(icon, size: 24, color: textColor.withValues(alpha: 0.55)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            if (isToggle)
              Switch(value: toggleValue ?? false, onChanged: (_) => onTap())
            else if (value.isNotEmpty)
              Text(
                value,
                style: TextStyle(fontSize: 14, color: subTextColor),
              ),
            if (!isToggle)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: textColor.withValues(alpha: 0.3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RevenueRow extends StatelessWidget {
  final String label;
  final String value;
  final Color textColor;
  final Color subTextColor;

  const _RevenueRow({
    required this.label,
    required this.value,
    required this.textColor,
    required this.subTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: subTextColor)),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
      ],
    );
  }
}

Future<bool?> showEditRestrictedBox(
  BuildContext context, {
  required String accountId,
  required String chatId,
  required MemberInfo member,
  bool isForum = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _EditRestrictedBox(
      accountId: accountId,
      chatId: chatId,
      member: member,
      isForum: isForum,
    ),
  );
}

enum _BanDuration { forever, oneDay, oneWeek, custom }

class _EditRestrictedBox extends StatefulWidget {
  final String accountId;
  final String chatId;
  final MemberInfo member;
  final bool isForum;

  const _EditRestrictedBox({
    required this.accountId,
    required this.chatId,
    required this.member,
    required this.isForum,
  });

  @override
  State<_EditRestrictedBox> createState() => _EditRestrictedBoxState();
}

class _EditRestrictedBoxState extends State<_EditRestrictedBox>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _saving = false;
  bool _mediaExpanded = false;
  String? _error;
  _BanDuration _duration = _BanDuration.forever;
  DateTime? _customDate;

  late AnimationController _expandCtrl;
  late Animation<double> _expandAnim;

  static const _kSecondsInDay = 86400;
  static const _kSecondsInWeek = 604800;
  static const _kMaxRestrictDelayDays = 366;

  late final _PermFlag _sendPlain;
  late final List<_PermFlag> _mediaFlags;
  late final List<_PermFlag> _otherFlags;

  List<_PermFlag> get _allFlags => [_sendPlain, ..._mediaFlags, ..._otherFlags];

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _expandAnim = CurvedAnimation(parent: _expandCtrl, curve: Curves.easeOutCubic);
    _sendPlain = _PermFlag(key: 'send_plain', label: 'Send text messages');
    _mediaFlags = [
      _PermFlag(key: 'send_photos', label: 'Send photos'),
      _PermFlag(key: 'send_videos', label: 'Send videos'),
      _PermFlag(key: 'send_roundvideos', label: 'Send video messages'),
      _PermFlag(key: 'send_audios', label: 'Send music'),
      _PermFlag(key: 'send_voices', label: 'Send voice messages'),
      _PermFlag(key: 'send_docs', label: 'Send files'),
      _PermFlag(key: 'send_stickers', label: 'Send stickers & GIFs'),
    ];
    _otherFlags = [
      _PermFlag(key: 'embed_links', label: 'Send links'),
      _PermFlag(key: 'send_polls', label: 'Send polls'),
      _PermFlag(key: 'invite_users', label: 'Add members'),
      if (widget.isForum) _PermFlag(key: 'manage_topics', label: 'Create topics'),
      _PermFlag(key: 'pin_messages', label: 'Pin messages'),
      _PermFlag(key: 'change_info', label: 'Change group info'),
    ];
    _loadDefaults();
  }

  @override
  void dispose() {
    _expandCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDefaults() async {
    try {
      final engine = context.read<EngineService>();
      Map<String, dynamic> rights;
      if (widget.member.role == 'restricted' || widget.member.role == 'banned') {
        try {
          final info = await engine.getParticipantInfo(
            widget.accountId,
            widget.chatId,
            widget.member.userId,
          );
          final bannedRights = info['banned_rights'] as Map<String, dynamic>?;
          if (bannedRights != null && bannedRights.isNotEmpty) {
            rights = bannedRights;
          } else {
            rights = await engine.getDefaultBannedRights(widget.accountId, widget.chatId);
          }
        } catch (_) {
          rights = await engine.getDefaultBannedRights(widget.accountId, widget.chatId);
        }
      } else {
        rights = await engine.getDefaultBannedRights(widget.accountId, widget.chatId);
      }
      if (!mounted) return;
      setState(() {
        for (final f in _allFlags) {
          f.banned = rights[f.key] == true;
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  int _computeUntilDate() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    switch (_duration) {
      case _BanDuration.forever:
        return 0;
      case _BanDuration.oneDay:
        return now + _kSecondsInDay;
      case _BanDuration.oneWeek:
        return now + _kSecondsInWeek;
      case _BanDuration.custom:
        if (_customDate != null) {
          return _customDate!.millisecondsSinceEpoch ~/ 1000;
        }
        return 0;
    }
  }

  Future<void> _onSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final engine = context.read<EngineService>();
      final rights = <String, bool>{};
      for (final f in _allFlags) {
        rights[f.key] = f.banned;
      }
      await engine.restrictMemberWithRights(
        widget.accountId,
        widget.chatId,
        widget.member.userId,
        rights,
        _computeUntilDate(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showTelegramToast(context, 'Failed: $e');
      }
    }
  }

  void _toggleFlag(_PermFlag flag) {
    setState(() {
      flag.banned = !flag.banned;
      if (flag.key == 'send_plain' && flag.banned) {
        final embedLinks = _otherFlags.firstWhere((f) => f.key == 'embed_links');
        embedLinks.banned = true;
      }
      if (flag.key == 'embed_links' && !flag.banned) {
        _sendPlain.banned = false;
      }
    });
  }

  int get _mediaAllowedCount => _mediaFlags.where((f) => !f.banned).length;

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final maxDate = now.add(const Duration(days: _kMaxRestrictDelayDays));
    final picked = await showDatePicker(
      context: context,
      initialDate: _customDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: maxDate,
    );
    if (picked != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_customDate ?? now),
      );
      if (mounted) {
        setState(() {
          _customDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            time?.hour ?? 0,
            time?.minute ?? 0,
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = PaletteProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE0E0E0);
    final accentColor = palette.windowBgActive;
    final attentionColor = palette.attentionButtonFg;
    final headerColor = palette.windowActiveTextFg;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: bgColor,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTitleBar(textColor, bgColor, accentColor, dividerColor),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_error!, style: TextStyle(color: attentionColor)),
              )
            else
              Flexible(
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    _buildCover(textColor, subTextColor, accentColor),
                    Divider(height: 1, color: dividerColor),
                    const SizedBox(height: 8),
                    _buildSectionHeader('What can this user do?', headerColor),
                    const SizedBox(height: 4),
                    _buildPermToggle(_sendPlain, accentColor, attentionColor, textColor),
                    _buildMediaSection(accentColor, attentionColor, textColor, subTextColor),
                    for (final f in _otherFlags)
                      _buildPermToggle(f, accentColor, attentionColor, textColor),
                    Divider(height: 1, color: dividerColor),
                    const SizedBox(height: 12),
                    _buildSectionHeader('Banned until', headerColor),
                    const SizedBox(height: 4),
                    _buildDurationPicker(accentColor, textColor, subTextColor),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar(Color textColor, Color bgColor, Color accentColor, Color dividerColor) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 8, top: 4, bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Restrict User',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
                ),
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                TextButton(
                  onPressed: _onSave,
                  child: Text('Save', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accentColor)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(fontSize: 14, color: textColor.withValues(alpha: 0.6))),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: dividerColor),
      ],
    );
  }

  Widget _buildCover(Color textColor, Color subTextColor, Color accentColor) {
    final member = widget.member;
    final hasAvatar = member.avatarB64.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 18, 20, 18),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: accentColor,
            backgroundImage: hasAvatar
                ? MemoryImage(base64Decode(member.avatarB64))
                : null,
            child: hasAvatar
                ? null
                : Text(
                    _initials(member.label),
                    style: const TextStyle(fontSize: 20, color: Colors.white),
                  ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  member.isOnline
                      ? 'online'
                      : member.username.isNotEmpty
                          ? '@${member.username}'
                          : member.role,
                  style: TextStyle(
                    fontSize: 13,
                    color: member.isOnline ? accentColor : subTextColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _buildPermToggle(_PermFlag flag, Color accentColor, Color attentionColor, Color textColor) {
    final allowed = !flag.banned;
    final isLocked = flag.key == 'embed_links' && _sendPlain.banned;

    return InkWell(
      onTap: () {
        if (isLocked) return;
        _toggleFlag(flag);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        child: Row(
          children: [
            if (isLocked)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.lock, size: 18, color: accentColor),
              ),
            Expanded(
              child: Text(
                flag.label,
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
            const SizedBox(width: 20),
            SizedBox(
              height: 24,
              child: Switch(
                value: allowed,
                onChanged: isLocked ? null : (_) => _toggleFlag(flag),
                activeColor: accentColor,
                inactiveThumbColor: attentionColor,
                inactiveTrackColor: attentionColor.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaSection(Color accentColor, Color attentionColor, Color textColor, Color subTextColor) {
    final allowedCount = _mediaAllowedCount;
    final total = _mediaFlags.length;

    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() => _mediaExpanded = !_mediaExpanded);
            if (_mediaExpanded) {
              _expandCtrl.forward();
            } else {
              _expandCtrl.reverse();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _expandAnim,
                  builder: (_, child) => Transform.rotate(
                    angle: _expandAnim.value * 3.14159,
                    child: child,
                  ),
                  child: Icon(Icons.expand_more, size: 20, color: textColor.withValues(alpha: 0.6)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Send media',
                    style: TextStyle(fontSize: 14, color: textColor),
                  ),
                ),
                Text(
                  '($allowedCount/$total)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: subTextColor),
                ),
                const SizedBox(width: 20),
                SizedBox(
                  height: 24,
                  child: Switch(
                    value: allowedCount == total,
                    onChanged: (val) {
                      setState(() {
                        for (final f in _mediaFlags) {
                          f.banned = !val;
                        }
                      });
                    },
                    activeColor: accentColor,
                    inactiveThumbColor: allowedCount == 0 ? attentionColor : accentColor,
                    inactiveTrackColor: allowedCount == 0
                        ? attentionColor.withValues(alpha: 0.3)
                        : accentColor.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizeTransition(
          sizeFactor: _expandAnim,
          child: Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Column(
              children: [
                for (final f in _mediaFlags)
                  _buildMediaCheckbox(f, accentColor, attentionColor, textColor),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaCheckbox(_PermFlag flag, Color accentColor, Color attentionColor, Color textColor) {
    final allowed = !flag.banned;
    return InkWell(
      onTap: () => _toggleFlag(flag),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: allowed,
                onChanged: (_) => _toggleFlag(flag),
                activeColor: accentColor,
                side: BorderSide(color: allowed ? accentColor : attentionColor, width: 2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(flag.label, style: TextStyle(fontSize: 14, color: textColor)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationPicker(Color accentColor, Color textColor, Color subTextColor) {
    return Column(
      children: [
        _buildDurationRadio(_BanDuration.forever, 'Ban forever', accentColor, textColor),
        _buildDurationRadio(_BanDuration.oneDay, 'Ban for 1 day', accentColor, textColor),
        _buildDurationRadio(_BanDuration.oneWeek, 'Ban for 1 week', accentColor, textColor),
        _buildDurationRadio(_BanDuration.custom, 'Custom...', accentColor, textColor),
        if (_duration == _BanDuration.custom && _customDate != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 0, 22, 8),
            child: Text(
              'Until ${_customDate!.year}-${_customDate!.month.toString().padLeft(2, '0')}-${_customDate!.day.toString().padLeft(2, '0')} '
              '${_customDate!.hour.toString().padLeft(2, '0')}:${_customDate!.minute.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 13, color: subTextColor),
            ),
          ),
      ],
    );
  }

  Widget _buildDurationRadio(_BanDuration value, String label, Color accentColor, Color textColor) {
    return InkWell(
      onTap: () {
        setState(() => _duration = value);
        if (value == _BanDuration.custom) {
          _pickCustomDate();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Radio<_BanDuration>(
                value: value,
                groupValue: _duration,
                onChanged: (v) {
                  setState(() => _duration = v!);
                  if (v == _BanDuration.custom) {
                    _pickCustomDate();
                  }
                },
                activeColor: accentColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 14, color: textColor)),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

Future<bool?> showEditAdminBox(
  BuildContext context, {
  required String accountId,
  required String chatId,
  required MemberInfo member,
  required bool isChannel,
  String? promotedBy,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _EditAdminBox(
      accountId: accountId,
      chatId: chatId,
      member: member,
      isChannel: isChannel,
      promotedBy: promotedBy,
    ),
  );
}

class _AdminFlag {
  final String key;
  final String label;
  bool enabled;

  _AdminFlag({required this.key, required this.label, this.enabled = true});
}

class _EditAdminBox extends StatefulWidget {
  final String accountId;
  final String chatId;
  final MemberInfo member;
  final bool isChannel;
  final String? promotedBy;

  const _EditAdminBox({
    required this.accountId,
    required this.chatId,
    required this.member,
    required this.isChannel,
    this.promotedBy,
  });

  @override
  State<_EditAdminBox> createState() => _EditAdminBoxState();
}

class _EditAdminBoxState extends State<_EditAdminBox>
    with SingleTickerProviderStateMixin {
  bool _addAsAdmin = true;
  bool _saving = false;
  late final TextEditingController _rankCtrl;

  late AnimationController _collapseCtrl;
  late Animation<double> _collapseAnim;

  late final List<_AdminFlag> _section1;
  late final List<_AdminFlag> _section2;
  late final List<_AdminFlag> _section3;
  late final List<_AdminFlag> _section4;

  List<_AdminFlag> get _allFlags => [
        ..._section1,
        ..._section2,
        ..._section3,
        if (widget.isChannel) ..._section4,
      ];

  bool get _allOwnerRightsSelected {
    for (final f in _allFlags) {
      if (!f.enabled) return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _rankCtrl = TextEditingController(text: widget.member.customRank);
    _collapseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0,
    );
    _collapseAnim = CurvedAnimation(parent: _collapseCtrl, curve: Curves.easeOutCubic);

    if (widget.isChannel) {
      _section1 = [
        _AdminFlag(key: 'change_info', label: 'Change channel info'),
      ];
      _section2 = [
        _AdminFlag(key: 'post_messages', label: 'Post messages'),
        _AdminFlag(key: 'edit_messages', label: 'Edit messages'),
        _AdminFlag(key: 'delete_messages', label: 'Delete messages'),
      ];
      _section3 = [
        _AdminFlag(key: 'post_stories', label: 'Post stories'),
        _AdminFlag(key: 'edit_stories', label: 'Edit stories'),
        _AdminFlag(key: 'delete_stories', label: 'Delete stories'),
      ];
      _section4 = [
        _AdminFlag(key: 'invite_users', label: 'Invite users via link'),
        _AdminFlag(key: 'manage_call', label: 'Manage voice chats'),
        _AdminFlag(key: 'manage_direct', label: 'Manage direct messages'),
        _AdminFlag(key: 'add_admins', label: 'Add new admins'),
        _AdminFlag(key: 'ban_users', label: 'Ban users'),
      ];
    } else {
      _section1 = [
        _AdminFlag(key: 'change_info', label: 'Change group info'),
        _AdminFlag(key: 'delete_messages', label: 'Delete messages'),
        _AdminFlag(key: 'ban_users', label: 'Ban users'),
        _AdminFlag(key: 'invite_users', label: 'Invite users via link'),
        _AdminFlag(key: 'manage_topics', label: 'Manage topics'),
        _AdminFlag(key: 'pin_messages', label: 'Pin messages'),
      ];
      _section2 = [
        _AdminFlag(key: 'post_stories', label: 'Post stories'),
        _AdminFlag(key: 'edit_stories', label: 'Edit stories'),
        _AdminFlag(key: 'delete_stories', label: 'Delete stories'),
      ];
      _section3 = [
        _AdminFlag(key: 'manage_call', label: 'Manage voice chats'),
        _AdminFlag(key: 'manage_ranks', label: 'Manage ranks'),
        _AdminFlag(key: 'anonymous', label: 'Remain anonymous'),
        _AdminFlag(key: 'add_admins', label: 'Add new admins'),
      ];
      _section4 = [];
    }

    if (widget.member.role == 'admin') {
      _addAsAdmin = true;
      _loadExistingRights();
    }
  }

  Future<void> _loadExistingRights() async {
    try {
      final engine = context.read<EngineService>();
      final info = await engine.getParticipantInfo(
        widget.accountId,
        widget.chatId,
        widget.member.userId,
      );
      if (!mounted || info.isEmpty) return;
      final rights = info['admin_rights'] as Map<String, dynamic>?;
      if (rights == null) return;
      setState(() {
        _rankCtrl.text = (info['rank'] as String?) ?? '';
        for (final f in _allFlags) {
          if (rights.containsKey(f.key)) {
            f.enabled = rights[f.key] == true;
          }
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _rankCtrl.dispose();
    _collapseCtrl.dispose();
    super.dispose();
  }

  void _toggleAddAsAdmin(bool val) {
    setState(() => _addAsAdmin = val);
    if (val) {
      _collapseCtrl.forward();
    } else {
      _collapseCtrl.reverse();
    }
  }

  Future<void> _onSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final engine = context.read<EngineService>();
      if (!_addAsAdmin) {
        await engine.demoteAdmin(widget.accountId, widget.chatId, widget.member.userId);
      } else {
        final rights = <String, bool>{};
        for (final f in _allFlags) {
          rights[f.key] = f.enabled;
        }
        await engine.promoteAdminWithRights(
          widget.accountId,
          widget.chatId,
          widget.member.userId,
          rights,
          _rankCtrl.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showTelegramToast(context, 'Failed: $e');
      }
    }
  }

  void _confirmDismiss() {
    final palette = PaletteProvider.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dismiss Admin'),
        content: const Text('Are you sure you want to remove this admin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: palette.attentionButtonFg),
            onPressed: () async {
              Navigator.pop(ctx);
              final engine = context.read<EngineService>();
              try {
                await engine.demoteAdmin(widget.accountId, widget.chatId, widget.member.userId);
                if (mounted) Navigator.pop(context, true);
              } catch (e) {
                if (mounted) {
                  showTelegramToast(context, 'Failed to dismiss: $e');
                }
              }
            },
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  void _confirmTransferOwnership() {
    final palette = PaletteProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    final label = widget.isChannel ? 'Channel' : 'Group';
    final passwordCtrl = TextEditingController();
    bool obscure = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: bgColor,
          title: Text(
            'Transfer $label Ownership',
            style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to transfer ownership of this $label to ${widget.member.label}? '
                'Please enter your 2FA password to confirm.',
                style: TextStyle(color: subTextColor, fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordCtrl,
                obscureText: obscure,
                autofocus: true,
                style: TextStyle(color: textColor, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const UnderlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: subTextColor),
                    onPressed: () => setDialogState(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: subTextColor)),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: palette.attentionButtonFg),
              onPressed: () async {
                final password = passwordCtrl.text;
                if (password.isEmpty) return;
                Navigator.pop(ctx);
                showTelegramToast(context, 'Transferring ownership...');
                try {
                  final engine = context.read<EngineService>();
                  await engine.transferChannelOwnership(
                    widget.accountId,
                    widget.chatId,
                    widget.member.userId,
                    password,
                  );
                  if (mounted) {
                    showTelegramToast(context, 'Ownership transferred successfully');
                    Navigator.of(context).pop(true);
                  }
                } catch (e) {
                  if (mounted) showTelegramToast(context, 'Transfer failed: $e');
                }
              },
              child: const Text('Transfer'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = PaletteProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE0E0E0);
    final accentColor = palette.windowBgActive;
    final attentionColor = palette.attentionButtonFg;
    final headerColor = palette.windowActiveTextFg;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: bgColor,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTitleBar(textColor, accentColor, dividerColor),
            Flexible(
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  _buildCover(textColor, subTextColor, accentColor),
                  Divider(height: 1, color: dividerColor),
                  const SizedBox(height: 8),
                  _buildAddAsAdminCheckbox(accentColor, textColor),
                  SizeTransition(
                    sizeFactor: _collapseAnim,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(height: 1, color: dividerColor),
                        const SizedBox(height: 8),
                        _buildSectionHeader(
                          'What can this admin do?',
                          headerColor,
                        ),
                        const SizedBox(height: 4),
                        _buildRightsSection(
                          widget.isChannel ? 'Info' : 'Core',
                          _section1,
                          accentColor,
                          textColor,
                        ),
                        Divider(height: 1, indent: 22, endIndent: 22, color: dividerColor),
                        _buildRightsSection(
                          widget.isChannel ? 'Messages' : 'Stories',
                          _section2,
                          accentColor,
                          textColor,
                        ),
                        Divider(height: 1, indent: 22, endIndent: 22, color: dividerColor),
                        _buildRightsSection(
                          widget.isChannel ? 'Stories' : 'Meta',
                          _section3,
                          accentColor,
                          textColor,
                        ),
                        if (widget.isChannel && _section4.isNotEmpty) ...[
                          Divider(height: 1, indent: 22, endIndent: 22, color: dividerColor),
                          _buildRightsSection('Meta', _section4, accentColor, textColor),
                        ],
                        Divider(height: 1, color: dividerColor),
                        const SizedBox(height: 8),
                        _buildRankField(textColor, subTextColor),
                        const SizedBox(height: 8),
                        if (_allOwnerRightsSelected) ...[
                          Divider(height: 1, color: dividerColor),
                          _buildTransferButton(accentColor, textColor),
                        ],
                      ],
                    ),
                  ),
                  if (widget.member.role == 'admin') ...[
                    Divider(height: 1, color: dividerColor),
                    const SizedBox(height: 4),
                    _buildDismissButton(attentionColor),
                    const SizedBox(height: 4),
                  ],
                  if (widget.promotedBy != null && widget.promotedBy!.isNotEmpty) ...[
                    Divider(height: 1, color: dividerColor),
                    _buildPromotedByInfo(subTextColor, accentColor),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar(Color textColor, Color accentColor, Color dividerColor) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 8, top: 4, bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Edit Admin',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
                ),
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                TextButton(
                  onPressed: _onSave,
                  child: Text('Save', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accentColor)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(fontSize: 14, color: textColor.withValues(alpha: 0.6))),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: dividerColor),
      ],
    );
  }

  Widget _buildCover(Color textColor, Color subTextColor, Color accentColor) {
    final member = widget.member;
    final hasAvatar = member.avatarB64.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 18, 20, 18),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: accentColor,
            backgroundImage: hasAvatar ? MemoryImage(base64Decode(member.avatarB64)) : null,
            child: hasAvatar
                ? null
                : Text(
                    _initials(member.label),
                    style: const TextStyle(fontSize: 20, color: Colors.white),
                  ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.label,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  member.isOnline
                      ? 'online'
                      : member.username.isNotEmpty
                          ? '@${member.username}'
                          : member.role,
                  style: TextStyle(
                    fontSize: 13,
                    color: member.isOnline ? accentColor : subTextColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddAsAdminCheckbox(Color accentColor, Color textColor) {
    return InkWell(
      onTap: () => _toggleAddAsAdmin(!_addAsAdmin),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: _addAsAdmin,
                onChanged: (v) => _toggleAddAsAdmin(v ?? false),
                activeColor: accentColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Add as Admin',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _buildRightsSection(
    String sectionLabel,
    List<_AdminFlag> flags,
    Color accentColor,
    Color textColor,
  ) {
    return Column(
      children: [
        for (final flag in flags)
          _buildRightToggle(flag, accentColor, textColor),
      ],
    );
  }

  Widget _buildRightToggle(_AdminFlag flag, Color accentColor, Color textColor) {
    return InkWell(
      onTap: () => setState(() => flag.enabled = !flag.enabled),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(flag.label, style: TextStyle(fontSize: 14, color: textColor)),
            ),
            const SizedBox(width: 20),
            SizedBox(
              height: 24,
              child: Switch(
                value: flag.enabled,
                onChanged: (v) => setState(() => flag.enabled = v),
                activeColor: accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRankField(Color textColor, Color subTextColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
      child: TextField(
        controller: _rankCtrl,
        maxLength: 16,
        style: TextStyle(fontSize: 14, color: textColor),
        decoration: InputDecoration(
          labelText: 'Custom Title',
          hintText: 'e.g. Head Moderator',
          hintStyle: TextStyle(color: subTextColor),
          counterText: '',
          isDense: true,
          border: const UnderlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildTransferButton(Color accentColor, Color textColor) {
    final label = widget.isChannel ? 'Transfer Channel Ownership' : 'Transfer Group Ownership';
    return InkWell(
      onTap: _confirmTransferOwnership,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.swap_horiz, size: 24, color: accentColor),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accentColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDismissButton(Color attentionColor) {
    return InkWell(
      onTap: _confirmDismiss,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.remove_circle_outline, size: 24, color: attentionColor),
            const SizedBox(width: 16),
            Text(
              'Dismiss Admin',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: attentionColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromotedByInfo(Color subTextColor, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
      child: Row(
        children: [
          Text(
            'Promoted by ',
            style: TextStyle(fontSize: 13, color: subTextColor),
          ),
          GestureDetector(
            onTap: () {
              final promoterId = widget.member.promotedByID;
              if (promoterId.isNotEmpty && InfoPanel.pushUserProfileRequest != null) {
                final promoterMember = MemberInfo(
                  userId: promoterId,
                  displayName: widget.promotedBy!,
                );
                InfoPanel.pushUserProfileRequest!(promoterMember);
                Navigator.of(context).pop();
              }
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Text(
                widget.promotedBy!,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: accentColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

// ══════════════════════════════════════════════════════════════
// §26.5 Admin Log / Recent Actions
// ══════════════════════════════════════════════════════════���═══

void showAdminLogScreen(
  BuildContext context, {
  required String accountId,
  required String chatId,
  required String chatTitle,
  required String chatAvatarPath,
  required bool isChannel,
}) {
  final engine = context.read<EngineService>();
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => Provider<EngineService>.value(
      value: engine,
      child: _AdminLogScreen(
        accountId: accountId,
        chatId: chatId,
        chatTitle: chatTitle,
        chatAvatarPath: chatAvatarPath,
        isChannel: isChannel,
      ),
    ),
  ));
}

class _AdminLogScreen extends StatefulWidget {
  final String accountId;
  final String chatId;
  final String chatTitle;
  final String chatAvatarPath;
  final bool isChannel;

  const _AdminLogScreen({
    required this.accountId,
    required this.chatId,
    required this.chatTitle,
    required this.chatAvatarPath,
    required this.isChannel,
  });

  @override
  State<_AdminLogScreen> createState() => _AdminLogScreenState();
}

class _AdminLogScreenState extends State<_AdminLogScreen> {
  final List<AdminLogEvent> _events = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  final _scrollCtrl = ScrollController();
  Map<String, bool>? _activeFilters;
  Map<String, bool>? _activeChecks;

  double _dateBadgeOpacity = 0.0;
  Timer? _dateHideTimer;
  String _currentDateLabel = '';
  final Map<int, GlobalKey> _itemKeys = {};
  final GlobalKey _listAreaKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadEvents();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    _dateHideTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEvents({bool append = false}) async {
    if (!append) {
      setState(() { _loading = true; _error = null; });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final engine = context.read<EngineService>();
      final limit = append ? 50 : 20;
      final maxId = append && _events.isNotEmpty ? _events.last.id : 0;
      final events = await engine.getAdminLogEvents(
        widget.accountId,
        widget.chatId,
        limit: limit,
        query: _searchQuery,
        maxId: maxId,
        filters: _activeFilters,
      );
      if (!mounted) return;
      setState(() {
        if (!append) {
          _events.clear();
          _itemKeys.clear();
        }
        _events.addAll(events);
        _hasMore = events.length >= limit;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      if (!_loadingMore && _hasMore) {
        _loadEvents(append: true);
      }
    }
    _updateDateBadge();
  }

  GlobalKey _getItemKey(int index) =>
      _itemKeys.putIfAbsent(index, () => GlobalKey());

  void _updateDateBadge() {
    if (_events.isEmpty) return;
    _dateHideTimer?.cancel();

    final containerRender =
        _listAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (containerRender == null) return;

    int firstVisibleIndex = 0;
    for (int i = 0; i < _events.length; i++) {
      final key = _itemKeys[i];
      if (key?.currentContext == null) continue;
      final renderBox =
          key!.currentContext!.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.attached) continue;
      final localPos = containerRender.globalToLocal(
        renderBox.localToGlobal(Offset.zero),
      );
      if (localPos.dy + renderBox.size.height > 0) {
        firstVisibleIndex = i;
        break;
      }
    }

    final event = _events[firstVisibleIndex];
    final date = DateTime.fromMillisecondsSinceEpoch(event.date * 1000);
    final newLabel = _formatDateHeader(date);

    setState(() {
      _currentDateLabel = newLabel;
      _dateBadgeOpacity = 1.0;
    });
    _dateHideTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _dateBadgeOpacity = 0.0);
    });
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _searchQuery = query);
      _loadEvents();
    });
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchCtrl.clear();
        if (_searchQuery.isNotEmpty) {
          _searchQuery = '';
          _loadEvents();
        }
      }
    });
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _AdminLogFilterDialog(
        isChannel: widget.isChannel,
        initialChecks: _activeChecks,
        onApply: (filters, checks) {
          _activeFilters = filters;
          _activeChecks = checks;
          _loadEvents();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = PaletteProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0E1621) : const Color(0xFFE6EBF0);
    final topBarBg = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    final shadowColor = palette.shadowFg;

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          _buildTopBar(topBarBg, textColor, subTextColor, shadowColor, palette),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(_error!, style: TextStyle(color: palette.attentionButtonFg)),
                        ),
                      )
                    : _events.isEmpty
                        ? _buildEmptyState(subTextColor)
                        : _buildEventList(palette, isDark, textColor, subTextColor),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(Color bg, Color textColor, Color subTextColor, Color shadowColor, TelegramPalette palette) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: bg,
        boxShadow: [BoxShadow(color: shadowColor, offset: const Offset(0, 1))],
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: textColor),
            onPressed: () => Navigator.pop(context),
          ),
          if (!_searchOpen) ...[
            _buildUserpic(palette),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.chatTitle,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 11),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  style: TextStyle(fontSize: 14, color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Search events...',
                    hintStyle: TextStyle(color: subTextColor),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
            ),
          IconButton(
            icon: Icon(
              _searchOpen ? Icons.close : Icons.search,
              color: textColor,
            ),
            onPressed: _toggleSearch,
          ),
          IconButton(
            icon: Icon(Icons.filter_list, color: textColor),
            onPressed: _showFilterDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildUserpic(TelegramPalette palette) {
    final path = widget.chatAvatarPath;
    final hasAvatar = path.isNotEmpty && File(path).existsSync();
    return CircleAvatar(
      radius: 17,
      backgroundColor: palette.windowBgActive,
      backgroundImage: hasAvatar ? FileImage(File(path)) : null,
      child: hasAvatar
          ? null
          : Text(
              widget.chatTitle.isNotEmpty ? widget.chatTitle[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
    );
  }

  Widget _buildEmptyState(Color subTextColor) {
    final bool hasFilter = _searchQuery.isNotEmpty;
    final String title;
    final String description;

    if (hasFilter) {
      title = 'No actions found';
      description = _searchQuery.trim().isNotEmpty
          ? "No recent actions that contain '${_searchQuery.trim()}' have been found."
          : 'No recent actions that match your query were found.';
    } else {
      title = 'No actions yet';
      description = widget.isChannel
          ? 'No notable actions taken\nby the admins of this channel\nin the last 48 hours.'
          : 'No notable actions taken by the members and admins of this group in the last 48 hours.';
    }

    return Center(
      child: SizedBox(
        width: 300,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: subTextColor),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: subTextColor, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEventList(TelegramPalette palette, bool isDark, Color textColor, Color subTextColor) {
    return Stack(
      key: _listAreaKey,
      children: [
        ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _events.length + (_loadingMore ? 1 : 0),
          itemBuilder: (ctx, i) {
            if (i >= _events.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            final event = _events[i];
            final showDateHeader = i == 0 || !_isSameDay(_events[i - 1].dateTime, event.dateTime);
            return Column(
              key: _getItemKey(i),
              children: [
                if (showDateHeader) _buildDateSeparator(event.dateTime, isDark),
                _AdminLogEventTile(
                  event: event,
                  palette: palette,
                  isDark: isDark,
                  textColor: textColor,
                  subTextColor: subTextColor,
                  isChannel: widget.isChannel,
                ),
              ],
            );
          },
        ),
        if (_events.isNotEmpty)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedOpacity(
                opacity: _dateBadgeOpacity,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xCC1B2734) : const Color(0xCCFFFFFF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _currentDateLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFAABBCC) : const Color(0xFF666666),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDateSeparator(DateTime date, bool isDark) {
    final label = _formatDateHeader(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xCC1B2734) : const Color(0xCCFFFFFF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFAABBCC) : const Color(0xFF666666),
            ),
          ),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatDateHeader(DateTime d) {
    final now = DateTime.now();
    if (_isSameDay(d, now)) return 'Today';
    final yesterday = now.subtract(const Duration(days: 1));
    if (_isSameDay(d, yesterday)) return 'Yesterday';
    const months = ['January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'];
    if (d.year == now.year) return '${months[d.month - 1]} ${d.day}';
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class _AdminLogEventTile extends StatelessWidget {
  final AdminLogEvent event;
  final TelegramPalette palette;
  final bool isDark;
  final Color textColor;
  final Color subTextColor;
  final bool isChannel;

  const _AdminLogEventTile({
    required this.event,
    required this.palette,
    required this.isDark,
    required this.textColor,
    required this.subTextColor,
    required this.isChannel,
  });

  @override
  Widget build(BuildContext context) {
    final serviceBg = isDark ? const Color(0xCC1B2734) : const Color(0xCCFFFFFF);
    final serviceText = isDark ? const Color(0xFFAABBCC) : const Color(0xFF666666);
    final accentColor = palette.windowBgActive;
    final time = _formatTime(event.dateTime);
    final desc = _actionDescription();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: serviceBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: event.userName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: accentColor,
                            ),
                          ),
                          TextSpan(
                            text: ' $desc',
                            style: TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: serviceText,
                            ),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      time,
                      style: TextStyle(fontSize: 11, color: subTextColor),
                    ),
                  ],
                ),
                if (event.msgText.isNotEmpty && event.action != 'edit_message')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: accentColor, width: 2),
                        ),
                        color: isDark
                            ? const Color(0x20FFFFFF)
                            : const Color(0x10000000),
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(6),
                          bottomRight: Radius.circular(6),
                        ),
                      ),
                      child: Text(
                        event.msgText,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: textColor),
                      ),
                    ),
                  ),
                if (event.oldValue.isNotEmpty && event.newValue.isNotEmpty &&
                    event.action == 'edit_message')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildQuotedBlock('Previous', event.oldValue, accentColor),
                        const SizedBox(height: 2),
                        _buildQuotedBlock('New', event.newValue, accentColor),
                      ],
                    ),
                  )
                else if (event.oldValue.isNotEmpty || event.newValue.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (event.oldValue.isNotEmpty)
                          _buildQuotedBlock('Previous', event.oldValue, accentColor),
                        if (event.newValue.isNotEmpty)
                          _buildQuotedBlock('New', event.newValue, accentColor),
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

  Widget _buildQuotedBlock(String label, String text, Color accentColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: accentColor, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: accentColor,
            ),
          ),
          Text(
            text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: textColor),
          ),
        ],
      ),
    );
  }

  String _actionDescription() {
    final memberLabel = isChannel ? 'subscriber' : 'member';
    switch (event.action) {
      case 'change_title':
        return 'changed the group title';
      case 'change_about':
        return 'changed the group description';
      case 'change_username':
        return 'changed the group link';
      case 'change_photo':
        return 'changed the group photo';
      case 'toggle_invites':
        return '${event.detail} invites';
      case 'toggle_signatures':
        return '${event.detail} signatures';
      case 'pin_message':
        return 'pinned a message';
      case 'unpin_message':
        return 'unpinned a message';
      case 'edit_message':
        return 'edited a message';
      case 'delete_message':
        return 'deleted a message';
      case 'participant_join':
        return 'joined the ${isChannel ? "channel" : "group"}';
      case 'participant_leave':
        return 'left the ${isChannel ? "channel" : "group"}';
      case 'participant_invite':
        return 'invited ${event.detail.isNotEmpty ? event.detail : "a $memberLabel"}';
      case 'participant_ban':
        return 'changed restrictions for ${event.detail.isNotEmpty ? event.detail : "a $memberLabel"}';
      case 'participant_admin':
        return 'changed admin rights for ${event.detail.isNotEmpty ? event.detail : "a $memberLabel"}';
      case 'change_stickerset':
        return 'changed the sticker set';
      case 'toggle_prehistory':
        return 'made chat history ${event.detail}';
      case 'change_default_rights':
        return 'changed default permissions';
      case 'stop_poll':
        return 'stopped a poll';
      case 'change_linked_chat':
        return 'changed the linked chat';
      case 'toggle_slowmode':
        return 'changed slow mode (${event.detail})';
      case 'start_call':
        return 'started a voice chat';
      case 'end_call':
        return 'ended a voice chat';
      case 'participant_mute':
        return 'muted a participant';
      case 'participant_unmute':
        return 'unmuted a participant';
      case 'call_setting':
        return 'changed call settings (${event.detail})';
      case 'join_by_invite':
        return 'joined via invite link';
      case 'invite_delete':
        return 'deleted an invite link';
      case 'invite_revoke':
        return 'revoked an invite link';
      case 'invite_edit':
        return 'edited an invite link';
      case 'change_ttl':
        return 'changed auto-delete timer (${event.detail})';
      case 'toggle_noforwards':
        return '${event.detail} content protection';
      case 'send_message':
        return 'sent a message';
      case 'toggle_forum':
        return '${event.detail} forum mode';
      case 'create_topic':
        return 'created a topic';
      case 'edit_topic':
        return 'edited a topic';
      case 'delete_topic':
        return 'deleted a topic';
      case 'pin_topic':
        return 'pinned a topic';
      case 'toggle_antispam':
        return '${event.detail} anti-spam';
      case 'change_reactions':
        return 'changed available reactions';
      case 'change_usernames':
        return 'changed usernames';
      case 'change_peer_color':
        return 'changed peer color';
      case 'change_profile_color':
        return 'changed profile color';
      case 'change_wallpaper':
        return 'changed wallpaper';
      case 'change_emoji_status':
        return 'changed emoji status';
      case 'change_emoji_stickerset':
        return 'changed emoji sticker set';
      case 'toggle_signature_profiles':
        return '${event.detail} signature profiles';
      case 'sub_extend':
        return 'extended subscription';
      case 'join_by_request':
        return 'was accepted to the group';
      case 'participant_volume':
        return 'changed participant volume';
      case 'change_location':
        if (event.detail.isEmpty) {
          return 'removed group location';
        }
        return 'changed group location to ${event.detail}';
      case 'toggle_autotranslation':
        return '${event.detail == "enabled" ? "enabled" : "disabled"} auto-translation';
      case 'participant_edit_rank':
        return 'changed custom title${event.detail.isNotEmpty ? ": ${event.detail}" : ""}';
      default:
        return event.detail.isNotEmpty ? event.detail : event.action;
    }
  }

  String _formatTime(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _AdminLogFilterDialog extends StatefulWidget {
  final bool isChannel;
  final Map<String, bool>? initialChecks;
  final void Function(Map<String, bool>? filters, Map<String, bool> checks) onApply;

  const _AdminLogFilterDialog({
    required this.isChannel,
    this.initialChecks,
    required this.onApply,
  });

  @override
  State<_AdminLogFilterDialog> createState() => _AdminLogFilterDialogState();
}

class _AdminLogFilterDialogState extends State<_AdminLogFilterDialog> {
  final Map<String, bool> _checks = {};

  static const _labelToFilterKeys = {
    'Admin rights': ['promote', 'demote'],
    'Edit rank': ['edit_rank'],
    'Restrictions': ['ban', 'unban', 'kick', 'unkick'],
    'New members': ['join', 'invite'],
    'Removed members': ['kick', 'leave'],
    'Info and settings': ['info', 'settings'],
    'Invite links': ['invites'],
    'Voice chats': ['group_call'],
    'Subscription extensions': ['sub_extend'],
    'Topics': ['forums'],
    'Deleted messages': ['delete'],
    'Edited messages': ['edit'],
    'Pinned messages': ['pinned'],
  };

  Map<String, bool>? _buildFilters() {
    final allChecked = _checks.values.every((v) => v);
    if (allChecked) return null;
    final filters = <String, bool>{};
    for (final entry in _checks.entries) {
      final keys = _labelToFilterKeys[entry.key];
      if (keys != null) {
        for (final k in keys) {
          filters[k] = (filters[k] ?? false) || entry.value;
        }
      }
    }
    return filters;
  }

  static const _memberSection = [
    'Admin rights',
    'Edit rank',
    'Restrictions',
    'New members',
    'Removed members',
  ];
  static const _settingsSection = [
    'Info and settings',
    'Invite links',
    'Voice chats',
    'Subscription extensions',
    'Topics',
  ];
  static const _messageSection = [
    'Deleted messages',
    'Edited messages',
    'Pinned messages',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialChecks != null) {
      _checks.addAll(widget.initialChecks!);
    } else {
      for (final s in [..._memberSection, ..._settingsSection, ..._messageSection]) {
        _checks[s] = true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = PaletteProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor = palette.windowBgActive;
    final headerColor = palette.windowActiveTextFg;
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE0E0E0);
    final memberLabel = widget.isChannel ? 'Subscribers' : 'Members';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: bgColor,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 8, top: 4, bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filter',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      widget.onApply(_buildFilters(), Map<String, bool>.from(_checks));
                      Navigator.pop(context);
                    },
                    child: Text('Apply', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accentColor)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(fontSize: 14, color: textColor.withValues(alpha: 0.6))),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: dividerColor),
            Flexible(
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  const SizedBox(height: 8),
                  _buildSection(memberLabel, _memberSection, headerColor, accentColor, textColor),
                  Divider(height: 1, color: dividerColor),
                  _buildSection('Settings', _settingsSection, headerColor, accentColor, textColor),
                  Divider(height: 1, color: dividerColor),
                  _buildSection('Messages', _messageSection, headerColor, accentColor, textColor),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    String title,
    List<String> items,
    Color headerColor,
    Color accentColor,
    Color textColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 4),
          child: Text(
            title,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: headerColor),
          ),
        ),
        for (final item in items)
          InkWell(
            onTap: () => setState(() => _checks[item] = !(_checks[item] ?? true)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _checks[item] ?? true,
                      onChanged: (v) => setState(() => _checks[item] = v ?? true),
                      activeColor: accentColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(item, style: TextStyle(fontSize: 14, color: textColor)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Invite Links Box (§26.6) ──

class _InviteLinkData {
  final String link;
  final String label;
  final String adminId;
  final int date;
  final int startDate;
  final int expireDate;
  final int usageLimit;
  final int usage;
  final int requested;
  final bool permanent;
  final bool revoked;
  final bool needApproval;
  final int subscriptionCredits;

  _InviteLinkData({
    required this.link,
    this.label = '',
    this.adminId = '',
    this.date = 0,
    this.startDate = 0,
    this.expireDate = 0,
    this.usageLimit = 0,
    this.usage = 0,
    this.requested = 0,
    this.permanent = false,
    this.revoked = false,
    this.needApproval = false,
    this.subscriptionCredits = 0,
  });

  factory _InviteLinkData.fromMap(Map<String, dynamic> m) {
    return _InviteLinkData(
      link: m['link'] as String? ?? '',
      label: m['label'] as String? ?? '',
      adminId: m['admin_id'] as String? ?? '',
      date: (m['date'] as num?)?.toInt() ?? 0,
      startDate: (m['start_date'] as num?)?.toInt() ?? 0,
      expireDate: (m['expire_date'] as num?)?.toInt() ?? 0,
      usageLimit: (m['usage_limit'] as num?)?.toInt() ?? 0,
      usage: (m['usage'] as num?)?.toInt() ?? 0,
      requested: (m['requested'] as num?)?.toInt() ?? 0,
      permanent: m['permanent'] as bool? ?? false,
      revoked: m['revoked'] as bool? ?? false,
      needApproval: m['need_approval'] as bool? ?? false,
      subscriptionCredits: (m['subscription_credits'] as num?)?.toInt() ?? 0,
    );
  }

  double get progress {
    if (permanent) return -1;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    double expProg = -1;
    double useProg = -1;
    if (expireDate > 0 && startDate > 0 && expireDate > startDate) {
      expProg = (now - startDate) / (expireDate - startDate);
    }
    if (usageLimit > 0) {
      useProg = usage / usageLimit;
    }
    if (expProg < 0 && useProg < 0) return -1;
    if (expProg < 0) return useProg;
    if (useProg < 0) return expProg;
    return expProg > useProg ? expProg : useProg;
  }

  String get displayName {
    if (label.isNotEmpty) return label;
    var s = link;
    s = s.replaceFirst('https://', '');
    s = s.replaceFirst('t.me/+', '');
    s = s.replaceFirst('t.me/joinchat/', '');
    return s;
  }

  String get statusText {
    final parts = <String>[];
    if (usage > 0) parts.add('$usage joined');
    if (usageLimit > 0) parts.add('${usageLimit - usage} remaining');
    if (expireDate > 0) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final remaining = expireDate - now;
      if (remaining > 0) {
        if (remaining > 86400) {
          parts.add('${remaining ~/ 86400}d left');
        } else if (remaining > 3600) {
          parts.add('${remaining ~/ 3600}h left');
        } else {
          parts.add('${remaining ~/ 60}m left');
        }
      } else {
        parts.add('expired');
      }
    }
    if (revoked) parts.add('revoked');
    if (parts.isEmpty) parts.add('no limit');
    return parts.join(' \u00b7 ');
  }
}

enum _LinkColorState { permanent, expiring, expireSoon, expired, revoked }

_LinkColorState _linkColorState(_InviteLinkData d) {
  if (d.revoked) return _LinkColorState.revoked;
  final p = d.progress;
  if (p < 0) return _LinkColorState.permanent;
  if (p >= 1.0) return _LinkColorState.expired;
  if (p >= 0.75) return _LinkColorState.expireSoon;
  return _LinkColorState.expiring;
}

Color _linkColor(_LinkColorState state, TelegramPalette palette) {
  switch (state) {
    case _LinkColorState.permanent:
      return palette.msgFile1Bg;
    case _LinkColorState.expiring:
      return palette.msgFile2Bg;
    case _LinkColorState.expireSoon:
      return palette.msgFile4Bg;
    case _LinkColorState.expired:
      return palette.msgFile3Bg;
    case _LinkColorState.revoked:
      return palette.windowSubTextFg;
  }
}

class _LinkArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  _LinkArcPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(r, r), r, paint);

    final icon = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(r, r), r * 0.55, icon);

    if (progress >= 0 && progress < 1.0) {
      final arcPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      const fullAngle = 2 * 3.14159265;
      final sweep = fullAngle * (1.0 - progress);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(r, r), radius: r - 1.5),
        -3.14159265 / 2,
        sweep,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_LinkArcPainter old) => old.progress != progress || old.color != color;
}

class _InviteLinksBox extends StatefulWidget {
  final String accountId;
  final String chatId;
  final bool isChannel;
  final String adminId;
  const _InviteLinksBox({required this.accountId, required this.chatId, required this.isChannel, this.adminId = ''});

  @override
  State<_InviteLinksBox> createState() => _InviteLinksBoxState();
}

class _InviteLinksBoxState extends State<_InviteLinksBox> {
  List<_InviteLinkData> _activeLinks = [];
  List<_InviteLinkData> _revokedLinks = [];
  List<Map<String, dynamic>> _adminsWithInvites = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final engine = context.read<EngineService>();
    try {
      final active = await engine.getExportedChatInvites(widget.accountId, widget.chatId, adminId: widget.adminId);
      final revoked = await engine.getExportedChatInvites(widget.accountId, widget.chatId, revoked: true, adminId: widget.adminId);
      List<Map<String, dynamic>> admins = [];
      if (widget.adminId.isEmpty) {
        try {
          admins = await engine.getAdminsWithInvites(widget.accountId, widget.chatId);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _activeLinks = active.map(_InviteLinkData.fromMap).toList();
          _revokedLinks = revoked.map(_InviteLinkData.fromMap).toList();
          _adminsWithInvites = admins;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showTelegramToast(context, 'Failed to load invite links: $e');
      }
    }
  }

  Future<void> _createNewLink() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _CreateEditLinkForm(
        accountId: widget.accountId,
        chatId: widget.chatId,
      ),
    );
    if (result != null) _loadAll();
  }

  Future<void> _revokeLink(_InviteLinkData link) async {
    final engine = context.read<EngineService>();
    try {
      await engine.revokeChatInviteLink(widget.accountId, widget.chatId, link.link);
      _loadAll();
    } catch (e) {
      if (mounted) {
        showTelegramToast(context, 'Failed: $e');
      }
    }
  }

  Future<void> _deleteLink(_InviteLinkData link) async {
    final engine = context.read<EngineService>();
    try {
      await engine.deleteRevokedChatInviteLink(widget.accountId, widget.chatId, link.link);
      _loadAll();
    } catch (e) {
      if (mounted) {
        showTelegramToast(context, 'Failed: $e');
      }
    }
  }

  Future<void> _deleteAllRevoked() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete All Revoked Links'),
        content: const Text('Are you sure you want to delete all revoked links?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final engine = context.read<EngineService>();
    try {
      await engine.deleteAllRevokedChatInvites(widget.accountId, widget.chatId);
      _loadAll();
    } catch (e) {
      if (mounted) {
        showTelegramToast(context, 'Failed: $e');
      }
    }
  }

  void _editLink(_InviteLinkData link) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _CreateEditLinkForm(
        accountId: widget.accountId,
        chatId: widget.chatId,
        existingLink: link,
      ),
    );
    if (result != null) _loadAll();
  }

  void _showLinkInfo(_InviteLinkData link) {
    showDialog(
      context: context,
      builder: (ctx) => _LinkInfoBox(
        accountId: widget.accountId,
        chatId: widget.chatId,
        link: link,
        onRevoke: () { Navigator.pop(ctx); _revokeLink(link); },
        onEdit: () { Navigator.pop(ctx); _editLink(link); },
        onDelete: link.revoked ? () { Navigator.pop(ctx); _deleteLink(link); } : null,
      ),
    );
  }

  void _showLinkContextMenu(_InviteLinkData link, TapDownDetails details) {
    final palette = PaletteProvider.of(context);
    final pos = details.globalPosition;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem(value: 'copy', child: Row(children: [
          Icon(Icons.copy, size: 20, color: palette.windowFg), const SizedBox(width: 12),
          const Text('Copy Link'),
        ])),
        PopupMenuItem(value: 'share', child: Row(children: [
          Icon(Icons.share, size: 20, color: palette.windowFg), const SizedBox(width: 12),
          const Text('Share Link'),
        ])),
        PopupMenuItem(value: 'qr', child: Row(children: [
          Icon(Icons.qr_code, size: 20, color: palette.windowFg), const SizedBox(width: 12),
          const Text('QR Code'),
        ])),
        if (!link.revoked) ...[
          PopupMenuItem(value: 'edit', child: Row(children: [
            Icon(Icons.edit, size: 20, color: palette.windowFg), const SizedBox(width: 12),
            const Text('Edit Link'),
          ])),
          PopupMenuItem(value: 'revoke', child: Row(children: [
            Icon(Icons.link_off, size: 20, color: palette.windowFg), const SizedBox(width: 12),
            const Text('Revoke Link'),
          ])),
        ],
        if (link.revoked)
          PopupMenuItem(value: 'delete', child: Row(children: [
            Icon(Icons.delete, size: 20, color: Theme.of(context).colorScheme.error), const SizedBox(width: 12),
            Text('Delete Link', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ])),
      ],
    ).then((action) {
      if (action == null) return;
      switch (action) {
        case 'copy':
          Clipboard.setData(ClipboardData(text: link.link));
          showTelegramToast(context, 'Link copied');
        case 'share':
          _shareLink(link.link);
        case 'qr':
          _showQrCodeDialog(link.link);
        case 'edit':
          _editLink(link);
        case 'revoke':
          _revokeLink(link);
        case 'delete':
          _deleteLink(link);
      }
    });
  }

  void _shareLink(String link) {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      Share.share(link);
    } else {
      Clipboard.setData(ClipboardData(text: link));
      showTelegramToast(context, 'Link copied to clipboard');
    }
  }

  void _showQrCodeDialog(String link) {
    showDialog(
      context: context,
      builder: (ctx) => _InviteLinkQrDialog(link: link),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = PaletteProvider.of(context);
    final textColor = palette.windowFg;
    final subColor = palette.windowSubTextFg;

    return Dialog(
      backgroundColor: palette.boxBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 364, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 8, 0),
              child: Row(
                children: [
                  Expanded(child: Text('Invite Links', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor))),
                  IconButton(icon: Icon(Icons.close, color: subColor, size: 20), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: _loading
                ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      ..._buildPermanentLink(palette, textColor, subColor),
                      _buildCreateButton(palette, textColor),
                      if (_activeLinks.where((l) => !l.permanent).isNotEmpty) ...[
                        _buildSectionHeader('My Links', textColor, subColor),
                        ..._activeLinks.where((l) => !l.permanent).map((l) => _buildLinkRow(l, palette, textColor, subColor)),
                      ],
                      if (_revokedLinks.isNotEmpty) ...[
                        _buildRevokedHeader(textColor, subColor),
                        ..._revokedLinks.map((l) => _buildLinkRow(l, palette, textColor, subColor)),
                      ],
                      if (_adminsWithInvites.isNotEmpty) ...[
                        _buildSectionHeader('Other Admins', textColor, subColor),
                        ..._adminsWithInvites.map((a) => _buildAdminRow(a, palette, textColor, subColor)),
                      ],
                    ],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPermanentLink(TelegramPalette palette, Color textColor, Color subColor) {
    final perm = _activeLinks.where((l) => l.permanent).toList();
    if (perm.isEmpty) return [];
    final link = perm.first;
    final colorState = _linkColorState(link);
    final color = _linkColor(colorState, palette);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 42, height: 42,
                child: CustomPaint(
                  painter: _LinkArcPainter(progress: link.progress, color: color),
                  child: Center(child: Icon(Icons.link, color: Colors.white, size: 18)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(link.displayName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(link.statusText, style: TextStyle(fontSize: 12, color: subColor)),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.copy, size: 20, color: palette.windowBgActive),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: link.link));
                  showTelegramToast(context, 'Link copied');
                },
              ),
              IconButton(
                icon: Icon(Icons.share, size: 20, color: palette.windowBgActive),
                onPressed: () => _shareLink(link.link),
              ),
              IconButton(
                icon: Icon(Icons.qr_code, size: 20, color: palette.windowBgActive),
                onPressed: () => _showQrCodeDialog(link.link),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildCreateButton(TelegramPalette palette, Color textColor) {
    return InkWell(
      onTap: _createNewLink,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 4),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: palette.windowBgActive,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_link, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Text('Create a New Link', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: palette.windowBgActive)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color textColor, Color subColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 4),
      child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.windowActiveTextFg)),
    );
  }

  TelegramPalette get palette => PaletteProvider.of(context);

  Widget _buildRevokedHeader(Color textColor, Color subColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 4),
      child: Row(
        children: [
          Expanded(child: Text('Revoked Links', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.windowActiveTextFg))),
          if (_revokedLinks.isNotEmpty)
            GestureDetector(
              onTap: _deleteAllRevoked,
              child: Text('Delete All', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }

  Widget _buildLinkRow(_InviteLinkData link, TelegramPalette palette, Color textColor, Color subColor) {
    final colorState = _linkColorState(link);
    final color = _linkColor(colorState, palette);
    return InkWell(
      onTap: () => _showLinkInfo(link),
      onSecondaryTapDown: (d) => _showLinkContextMenu(link, d),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 42, height: 42,
              child: CustomPaint(
                painter: _LinkArcPainter(progress: link.progress, color: color),
                child: Center(child: Icon(Icons.link, color: Colors.white, size: 16)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(link.displayName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(link.statusText, style: TextStyle(fontSize: 12, color: subColor)),
                ],
              ),
            ),
            GestureDetector(
              onTapDown: (d) => _showLinkContextMenu(link, d),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.more_vert, size: 18, color: subColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminRow(Map<String, dynamic> admin, TelegramPalette palette, Color textColor, Color subColor) {
    final name = admin['admin_name'] as String? ?? 'Admin';
    final adminId = admin['admin_id'] as String? ?? '';
    final count = admin['invites_count'] as int? ?? 0;
    final revokedCount = admin['revoked_invites_count'] as int? ?? 0;
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (ctx) => Provider<EngineService>.value(
            value: context.read<EngineService>(),
            child: _InviteLinksBox(
              accountId: widget.accountId,
              chatId: widget.chatId,
              isChannel: widget.isChannel,
              adminId: adminId,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
        child: Row(
          children: [
            CircleAvatar(radius: 21, backgroundColor: palette.windowBgActive,
              child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 16))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textColor)),
                  const SizedBox(height: 2),
                  Text('$count links${revokedCount > 0 ? ', $revokedCount revoked' : ''}',
                    style: TextStyle(fontSize: 12, color: subColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── QR Code Dialog (§26.6.5) ──

class _InviteLinkQrDialog extends StatelessWidget {
  final String link;
  const _InviteLinkQrDialog({required this.link});

  @override
  Widget build(BuildContext context) {
    final palette = PaletteProvider.of(context);
    final displayUrl = link.replaceFirst(RegExp(r'^https?://'), '');
    const boxWidth = 320.0;
    const padding = 22.0;
    final qrSize = boxWidth - padding * 2;
    return Dialog(
      backgroundColor: palette.boxBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: SizedBox(
        width: boxWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 8, 0),
              child: Row(
                children: [
                  Expanded(child: Text('QR Code', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: palette.windowFg))),
                  IconButton(icon: Icon(Icons.close, color: palette.windowSubTextFg, size: 20), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            QrImageView(
              data: link,
              version: QrVersions.auto,
              size: qrSize,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
              dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(displayUrl, style: TextStyle(fontSize: 13, color: palette.windowSubTextFg), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    icon: Icon(Icons.copy, size: 18, color: palette.windowBgActive),
                    label: Text('Copy', style: TextStyle(color: palette.windowBgActive)),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: link));
                      showTelegramToast(context, 'Link copied');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ── Single Link Info Box (§26.6.4) ──

class _LinkInfoBox extends StatelessWidget {
  final String accountId;
  final String chatId;
  final _InviteLinkData link;
  final VoidCallback? onRevoke;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _LinkInfoBox({
    required this.accountId,
    required this.chatId,
    required this.link,
    this.onRevoke,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final palette = PaletteProvider.of(context);
    final textColor = palette.windowFg;
    final subColor = palette.windowSubTextFg;
    final colorState = _linkColorState(link);
    final color = _linkColor(colorState, palette);

    return Dialog(
      backgroundColor: palette.boxBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 364),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Invite Link', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
                  const Spacer(),
                  IconButton(icon: Icon(Icons.close, size: 20, color: subColor), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: link.link));
                    showTelegramToast(context, 'Link copied');
                  },
                  child: Text(
                    link.link.replaceFirst('https://', ''),
                    style: TextStyle(fontSize: 14, color: palette.windowBgActive),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (!link.revoked && link.progress < 1.0) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: link.link));
                          showTelegramToast(context, 'Link copied');
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
                            Share.share(link.link);
                          } else {
                            Clipboard.setData(ClipboardData(text: link.link));
                            showTelegramToast(context, 'Link copied to clipboard');
                          }
                        },
                        icon: const Icon(Icons.share, size: 18),
                        label: const Text('Share'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Divider(color: subColor.withValues(alpha: 0.2)),
              const SizedBox(height: 4),
              _infoRow('Joined', '${link.usage}', textColor, subColor),
              if (link.usageLimit > 0)
                _infoRow('Remaining', '${link.usageLimit - link.usage}', textColor, subColor),
              if (link.expireDate > 0)
                _infoRow('Expires', _formatExpiry(link.expireDate), textColor, subColor),
              if (link.requested > 0)
                _infoRow('Pending', '${link.requested}', textColor, subColor),
              const SizedBox(height: 8),
              if (!link.revoked) ...[
                if (onEdit != null)
                  TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit, size: 18), label: const Text('Edit Link')),
                if (onRevoke != null)
                  TextButton.icon(
                    onPressed: onRevoke,
                    icon: Icon(Icons.link_off, size: 18, color: Theme.of(context).colorScheme.error),
                    label: Text('Revoke Link', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ],
              if (link.revoked && onDelete != null)
                TextButton.icon(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete, size: 18, color: Theme.of(context).colorScheme.error),
                  label: Text('Delete Link', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, Color textColor, Color subColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: subColor)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textColor)),
        ],
      ),
    );
  }

  String _formatExpiry(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    if (dt.isBefore(now)) return 'Expired';
    final diff = dt.difference(now);
    if (diff.inDays > 0) return 'in ${diff.inDays}d';
    if (diff.inHours > 0) return 'in ${diff.inHours}h';
    return 'in ${diff.inMinutes}m';
  }
}

// ── Create / Edit Link Form (§26.6.6) ──

class _CreateEditLinkForm extends StatefulWidget {
  final String accountId;
  final String chatId;
  final _InviteLinkData? existingLink;
  const _CreateEditLinkForm({required this.accountId, required this.chatId, this.existingLink});

  @override
  State<_CreateEditLinkForm> createState() => _CreateEditLinkFormState();
}

class _CreateEditLinkFormState extends State<_CreateEditLinkForm> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _creditsCtrl;
  int _expireOption = 0;
  int _usageLimitOption = 0;
  bool _requestApproval = false;
  bool _subscription = false;
  bool _subscriptionLocked = false;
  bool _saving = false;

  bool get _isEdit => widget.existingLink != null;

  static const _expireOptions = <int, String>{
    0: 'Never',
    3600: '1 hour',
    86400: '1 day',
    604800: '7 days',
    -1: 'Custom',
  };

  static const _usageOptions = <int, String>{
    0: 'Unlimited',
    1: '1 use',
    10: '10 uses',
    100: '100 uses',
    -1: 'Custom',
  };

  int _customExpireSeconds = 0;
  int _customUsageLimit = 0;

  String _formatCustomExpiry() {
    final target = DateTime.now().add(Duration(seconds: _customExpireSeconds));
    return '${target.day}/${target.month}/${target.year} ${target.hour.toString().padLeft(2, '0')}:${target.minute.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.existingLink?.label ?? '');
    _subscriptionLocked = (widget.existingLink?.subscriptionCredits ?? 0) > 0;
    _subscription = _subscriptionLocked;
    _creditsCtrl = TextEditingController(
      text: (widget.existingLink?.subscriptionCredits ?? 0) > 0
          ? '${widget.existingLink!.subscriptionCredits}'
          : '',
    );
    if (_isEdit) {
      final el = widget.existingLink!;
      _requestApproval = el.needApproval;
      if (el.expireDate > 0) {
        final dur = el.expireDate - (el.startDate > 0 ? el.startDate : el.date);
        final matched = _expireOptions.keys.where((k) => k > 0).cast<int?>().firstWhere(
          (k) => (dur - k!).abs() < k * 0.1,
          orElse: () => null,
        );
        if (matched != null) {
          _expireOption = matched;
        } else {
          _expireOption = -1;
          _customExpireSeconds = dur;
        }
      } else {
        _expireOption = 0;
      }
      if (_usageOptions.keys.contains(el.usageLimit)) {
        _usageLimitOption = el.usageLimit;
      } else if (el.usageLimit > 0) {
        _usageLimitOption = -1;
        _customUsageLimit = el.usageLimit;
      } else {
        _usageLimitOption = 0;
      }
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _creditsCtrl.dispose();
    super.dispose();
  }

  Future<void> _showCustomExpiry() async {
    final now = DateTime.now();
    final result = await showChooseDateTimeBox(
      context,
      initialDate: now.add(const Duration(days: 1)),
      title: 'Set Expiry Date',
      submitText: 'Set',
      showRepeat: false,
    );
    if (result == null || !mounted) return;
    final diffSeconds = result.dateTime.difference(now).inSeconds;
    if (diffSeconds > 0) {
      setState(() {
        _customExpireSeconds = diffSeconds;
        _expireOption = -1;
      });
    }
  }

  Future<void> _showCustomUsageLimit() async {
    final controller = TextEditingController();
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        final palette = PaletteProvider.of(ctx);
        return AlertDialog(
          backgroundColor: palette.boxBg,
          title: Text('Custom Usage Limit', style: TextStyle(color: palette.windowFg)),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Enter number (1–200000)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final val = int.tryParse(controller.text.trim());
                if (val != null && val >= 1 && val <= 200000) {
                  Navigator.pop(ctx, val);
                }
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result != null && mounted) {
      setState(() {
        _customUsageLimit = result;
        _usageLimitOption = -1;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final engine = context.read<EngineService>();
    final label = _labelCtrl.text.trim();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final int expireDate;
    if (_expireOption == -1) {
      expireDate = now + _customExpireSeconds;
    } else if (_expireOption > 0) {
      expireDate = now + _expireOption;
    } else {
      expireDate = 0;
    }
    final usageLimit = _requestApproval ? 0 : (_usageLimitOption == -1 ? _customUsageLimit : _usageLimitOption);
    final subscriptionCredits = _subscription
        ? (int.tryParse(_creditsCtrl.text.trim()) ?? 0)
        : 0;

    try {
      if (_isEdit) {
        await engine.editChatInviteLink(
          widget.accountId, widget.chatId, widget.existingLink!.link,
          label: label, expireDate: expireDate, usageLimit: usageLimit,
          requestApproval: _requestApproval,
          subscriptionCredits: subscriptionCredits,
        );
      } else {
        await engine.createChatInviteLink(
          widget.accountId, widget.chatId,
          label: label, expireDate: expireDate, usageLimit: usageLimit,
          requestApproval: _requestApproval,
          subscriptionCredits: subscriptionCredits,
        );
      }
      if (mounted) Navigator.pop(context, {'ok': true});
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showTelegramToast(context, 'Failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = PaletteProvider.of(context);
    final textColor = palette.windowFg;
    final subColor = palette.windowSubTextFg;

    return Dialog(
      backgroundColor: palette.boxBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 364),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(_isEdit ? 'Edit Link' : 'Create New Link',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor))),
                  IconButton(icon: Icon(Icons.close, size: 20, color: subColor), onPressed: () => Navigator.pop(context)),
                ],
              ),
              // Request Approval toggle (first per AyuGram order)
              if (!_subscriptionLocked) ...[
              const SizedBox(height: 16),
              SwitchListTile(
                title: Text('Approve New Members', style: TextStyle(fontSize: 14, color: textColor)),
                subtitle: Text('Requests to join must be approved by an admin', style: TextStyle(fontSize: 12, color: subColor)),
                value: _requestApproval,
                onChanged: (v) => setState(() => _requestApproval = v),
                activeTrackColor: palette.windowBgActive,
                contentPadding: EdgeInsets.zero,
              ),
              ],
              // Subscription toggle (SwitchListTile, not Checkbox)
              const SizedBox(height: 4),
              SwitchListTile(
                title: Text('Subscription', style: TextStyle(fontSize: 14, color: textColor)),
                subtitle: Text('Users will pay star credits to subscribe via this link.',
                  style: TextStyle(fontSize: 12, color: subColor)),
                value: _subscription,
                onChanged: (_saving || _subscriptionLocked)
                    ? (_subscriptionLocked
                        ? (_) { showTelegramToast(context, 'Subscription links cannot be changed after creation.'); }
                        : null)
                    : (v) => setState(() {
                          _subscription = v;
                          if (_subscription) _requestApproval = false;
                        }),
                activeTrackColor: palette.windowBgActive,
                contentPadding: EdgeInsets.zero,
              ),
              if (_subscription) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: SizedBox(
                    width: 180,
                    child: TextField(
                      controller: _creditsCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      enabled: !_saving && !_subscriptionLocked,
                      decoration: InputDecoration(
                        labelText: 'Star credits',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                ),
              ],
              // Label field (after toggles, before expire/usage)
              const SizedBox(height: 16),
              Text('Link Name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.windowActiveTextFg)),
              const SizedBox(height: 8),
              TextField(
                controller: _labelCtrl,
                maxLength: 32,
                decoration: InputDecoration(
                  hintText: 'Label (optional)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  counterText: '',
                ),
              ),
              // Expire options (Radio buttons, not ChoiceChips)
              if (!_subscriptionLocked) ...[
              const SizedBox(height: 16),
              Text('Expire After', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.windowActiveTextFg)),
              const SizedBox(height: 4),
              ..._expireOptions.entries.map((e) => RadioListTile<int>(
                title: Text(
                  e.key == -1 && _expireOption == -1 && _customExpireSeconds > 0
                    ? 'Custom (${_formatCustomExpiry()})'
                    : e.value,
                  style: TextStyle(fontSize: 14, color: textColor),
                ),
                value: e.key,
                groupValue: _expireOption,
                activeColor: palette.windowBgActive,
                dense: true,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onChanged: (v) {
                  if (v == -1) {
                    _showCustomExpiry();
                  } else {
                    setState(() => _expireOption = v!);
                  }
                },
              )),
              // Usage limit (Radio buttons, hidden when requestApproval is on)
              if (!_requestApproval) ...[
                const SizedBox(height: 16),
                Text('Usage Limit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.windowActiveTextFg)),
                const SizedBox(height: 4),
                ..._usageOptions.entries.map((e) => RadioListTile<int>(
                  title: Text(
                    e.key == -1 && _usageLimitOption == -1 && _customUsageLimit > 0
                      ? 'Custom ($_customUsageLimit uses)'
                      : e.value,
                    style: TextStyle(fontSize: 14, color: textColor),
                  ),
                  value: e.key,
                  groupValue: _usageLimitOption,
                  activeColor: palette.windowBgActive,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) {
                    if (v == -1) {
                      _showCustomUsageLimit();
                    } else {
                      setState(() => _usageLimitOption = v!);
                    }
                  },
                )),
              ],
              ], // end if (!_subscriptionLocked)
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 42,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.windowBgActive,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_isEdit ? 'Save' : 'Create', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// §26.7–26.8  Member List with Role Tabs
// ═══════════════════════════════════════════════════════════════════════

enum _MemberTab { members, admins, restricted, kicked, requests }

void showMemberListScreen(
  BuildContext context, {
  required String accountId,
  required String chatId,
  required bool isChannel,
  _MemberTab initialTab = _MemberTab.members,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _MemberListScreen(
        accountId: accountId,
        chatId: chatId,
        isChannel: isChannel,
        initialTab: initialTab,
      ),
    ),
  );
}

class _MemberListScreen extends StatefulWidget {
  final String accountId;
  final String chatId;
  final bool isChannel;
  final _MemberTab initialTab;

  const _MemberListScreen({
    required this.accountId,
    required this.chatId,
    required this.isChannel,
    required this.initialTab,
  });

  @override
  State<_MemberListScreen> createState() => _MemberListScreenState();
}

class _MemberListScreenState extends State<_MemberListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';

  final Map<_MemberTab, List<MemberInfo>> _members = {};
  final Map<_MemberTab, bool> _loading = {};
  final Map<_MemberTab, bool> _hasMore = {};
  final Map<_MemberTab, int> _offsets = {};

  static const _firstPageCount = 16;
  static const _pageSize = 200;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: _MemberTab.values.length,
      vsync: this,
      initialIndex: widget.initialTab.index,
    );
    _tabCtrl.addListener(_onTabChanged);
    for (final tab in _MemberTab.values) {
      _members[tab] = [];
      _loading[tab] = false;
      _hasMore[tab] = true;
      _offsets[tab] = 0;
    }
    _loadPage(_tabCtrl.index == 0 ? _MemberTab.values[0] : widget.initialTab);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabCtrl.indexIsChanging) return;
    final tab = _MemberTab.values[_tabCtrl.index];
    if (_members[tab]!.isEmpty && _hasMore[tab]!) {
      _loadPage(tab);
    }
  }

  void _onSearchChanged(String text) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      setState(() => _searchQuery = text.trim());
      for (final tab in _MemberTab.values) {
        _members[tab] = [];
        _offsets[tab] = 0;
        _hasMore[tab] = true;
      }
      _loadPage(_MemberTab.values[_tabCtrl.index]);
    });
  }

  String _roleForTab(_MemberTab tab) {
    switch (tab) {
      case _MemberTab.members:
        return 'members';
      case _MemberTab.admins:
        return 'admins';
      case _MemberTab.restricted:
        return 'restricted';
      case _MemberTab.kicked:
        return 'kicked';
      case _MemberTab.requests:
        return 'requests';
    }
  }

  Future<void> _loadPage(_MemberTab tab) async {
    if (_loading[tab]! || !_hasMore[tab]!) return;
    setState(() => _loading[tab] = true);

    final engine = context.read<EngineService>();
    final offset = _offsets[tab]!;
    final limit = offset == 0 ? _firstPageCount : _pageSize;

    try {
      final result = await engine.getChatMembersByRole(
        widget.accountId,
        widget.chatId,
        role: _roleForTab(tab),
        query: _searchQuery,
        limit: limit,
        offset: offset,
      );
      if (!mounted) return;
      setState(() {
        _members[tab]!.addAll(result.members);
        _offsets[tab] = _offsets[tab]! + result.members.length;
        _hasMore[tab] = result.members.length >= limit;
        _loading[tab] = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading[tab] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = PaletteProvider.of(context);
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF222222);
    final subColor = isDark ? const Color(0xFF8B9EB0) : const Color(0xFF999999);
    final accentColor = palette.windowBgActive;
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE0E0E0);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        title: Text(
          widget.isChannel ? 'Subscribers' : 'Members',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(90),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    style: TextStyle(fontSize: 14, color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Search',
                      hintStyle: TextStyle(fontSize: 14, color: subColor),
                      prefixIcon: Icon(Icons.search, size: 20, color: subColor),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF242F3D) : const Color(0xFFF1F1F1),
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              TabBar(
                controller: _tabCtrl,
                labelColor: accentColor,
                unselectedLabelColor: subColor,
                indicatorColor: accentColor,
                indicatorSize: TabBarIndicatorSize.label,
                isScrollable: true,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 13),
                tabs: [
                  Tab(text: widget.isChannel ? 'Subscribers' : 'Members'),
                  const Tab(text: 'Admins'),
                  const Tab(text: 'Restricted'),
                  const Tab(text: 'Removed'),
                  const Tab(text: 'Requests'),
                ],
              ),
              Divider(height: 1, color: dividerColor),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: _MemberTab.values.map((tab) {
          return _MemberTabBody(
            members: _members[tab]!,
            loading: _loading[tab]!,
            hasMore: _hasMore[tab]!,
            tab: tab,
            isChannel: widget.isChannel,
            accountId: widget.accountId,
            chatId: widget.chatId,
            onLoadMore: () => _loadPage(tab),
            onRefresh: () {
              _members[tab] = [];
              _offsets[tab] = 0;
              _hasMore[tab] = true;
              _loadPage(tab);
            },
            textColor: textColor,
            subColor: subColor,
            accentColor: accentColor,
            isDark: isDark,
          );
        }).toList(),
      ),
    );
  }
}

class _MemberTabBody extends StatelessWidget {
  final List<MemberInfo> members;
  final bool loading;
  final bool hasMore;
  final _MemberTab tab;
  final bool isChannel;
  final String accountId;
  final String chatId;
  final VoidCallback onLoadMore;
  final VoidCallback onRefresh;
  final Color textColor;
  final Color subColor;
  final Color accentColor;
  final bool isDark;

  const _MemberTabBody({
    required this.members,
    required this.loading,
    required this.hasMore,
    required this.tab,
    required this.isChannel,
    required this.accountId,
    required this.chatId,
    required this.onLoadMore,
    required this.onRefresh,
    required this.textColor,
    required this.subColor,
    required this.accentColor,
    required this.isDark,
  });

  bool get _showAddButton =>
      tab == _MemberTab.kicked ||
      tab == _MemberTab.restricted ||
      tab == _MemberTab.admins;

  String get _addButtonLabel => switch (tab) {
    _MemberTab.kicked => 'Add to Banned',
    _MemberTab.restricted => 'Add Exception',
    _MemberTab.admins => 'Add Admin',
    _ => 'Add Member',
  };

  IconData get _addButtonIcon => switch (tab) {
    _MemberTab.kicked => Icons.person_off_outlined,
    _MemberTab.restricted => Icons.person_add_outlined,
    _MemberTab.admins => Icons.admin_panel_settings_outlined,
    _ => Icons.person_add_outlined,
  };

  @override
  Widget build(BuildContext context) {
    if (loading && members.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final hasAdd = _showAddButton;
    final emptyContent = members.isEmpty && !hasAdd;

    if (emptyContent) {
      return Center(
        child: Text(
          tab == _MemberTab.kicked
              ? 'No removed users'
              : tab == _MemberTab.restricted
                  ? 'No restricted users'
                  : 'No participants found',
          style: TextStyle(fontSize: 14, color: subColor),
        ),
      );
    }

    final addOffset = hasAdd ? 1 : 0;

    return NotificationListener<ScrollNotification>(
      onNotification: (notif) {
        if (notif is ScrollEndNotification &&
            notif.metrics.pixels >= notif.metrics.maxScrollExtent - 100 &&
            hasMore &&
            !loading) {
          onLoadMore();
        }
        return false;
      },
      child: ListView.builder(
        itemCount: members.length + addOffset + (loading ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (hasAdd && i == 0) {
            return _buildAddButton(ctx);
          }
          final memberIdx = i - addOffset;
          if (memberIdx >= members.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final m = members[memberIdx];
          return _MemberRow(
            member: m,
            tab: tab,
            isChannel: isChannel,
            accountId: accountId,
            chatId: chatId,
            textColor: textColor,
            subColor: subColor,
            accentColor: accentColor,
            isDark: isDark,
            onRefresh: onRefresh,
          );
        },
      ),
    );
  }

  Widget _buildAddButton(BuildContext ctx) {
    return InkWell(
      onTap: () => _showAddMemberDialog(ctx),
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: accentColor,
                child: Icon(_addButtonIcon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                _addButtonLabel,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddMemberDialog(BuildContext ctx) {
    final isDarkLocal = isDark;
    final bgColor = isDarkLocal ? const Color(0xFF1E2C3A) : Colors.white;
    final textColorLocal = isDarkLocal ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subColorLocal = isDarkLocal ? const Color(0xFF708499) : const Color(0xFF999999);
    final searchCtrl = TextEditingController();
    final action = tab == _MemberTab.kicked ? 'ban' : tab == _MemberTab.admins ? 'promote' : 'restrict';
    final title = tab == _MemberTab.kicked ? 'Ban User' : tab == _MemberTab.admins ? 'Add Admin' : 'Add Exception';

    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text(
          title,
          style: TextStyle(color: textColorLocal, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: searchCtrl,
              autofocus: true,
              style: TextStyle(color: textColorLocal, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Enter username or user ID',
                hintStyle: TextStyle(color: subColorLocal),
                prefixIcon: Icon(Icons.search, color: subColorLocal),
                border: const UnderlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter the username or user ID of the person to $action.',
              style: TextStyle(color: subColorLocal, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: TextStyle(color: subColorLocal)),
          ),
          TextButton(
            onPressed: () async {
              final input = searchCtrl.text.trim();
              if (input.isEmpty) return;
              Navigator.pop(dialogCtx);
              final engine = ctx.read<EngineService>();
              try {
                String userId;
                final isNumeric = RegExp(r'^\d+$').hasMatch(input);
                if (isNumeric) {
                  userId = input;
                } else {
                  final stripped = input.startsWith('@') ? input.substring(1) : input;
                  if (ctx.mounted) showTelegramToast(ctx, 'Resolving user...');
                  final resolved = await engine.resolveUsername(accountId, stripped);
                  if (resolved == null || resolved.isEmpty) {
                    if (ctx.mounted) showTelegramToast(ctx, 'User not found: $input');
                    return;
                  }
                  userId = resolved;
                }
                if (tab == _MemberTab.kicked) {
                  await engine.banMember(accountId, chatId, userId);
                } else if (tab == _MemberTab.admins) {
                  await engine.promoteAdmin(accountId, chatId, userId);
                } else {
                  await engine.restrictMember(accountId, chatId, userId);
                }
                onRefresh();
                if (ctx.mounted) showTelegramToast(ctx, 'User ${action}ed successfully');
              } catch (e) {
                if (ctx.mounted) showTelegramToast(ctx, 'Failed to $action user: $e');
              }
            },
            child: Text('Confirm', style: TextStyle(color: accentColor, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final MemberInfo member;
  final _MemberTab tab;
  final bool isChannel;
  final String accountId;
  final String chatId;
  final Color textColor;
  final Color subColor;
  final Color accentColor;
  final bool isDark;
  final VoidCallback onRefresh;

  const _MemberRow({
    required this.member,
    required this.tab,
    required this.isChannel,
    required this.accountId,
    required this.chatId,
    required this.textColor,
    required this.subColor,
    required this.accentColor,
    required this.isDark,
    required this.onRefresh,
  });

  String _statusText() {
    if (member.customRank.isNotEmpty) return member.customRank;
    switch (member.role) {
      case 'creator':
        return 'owner';
      case 'admin':
        return 'admin';
      case 'restricted':
        return 'restricted';
      case 'banned':
        return 'banned';
      default:
        if (member.isBot) return 'bot';
        if (member.isOnline) return 'online';
        return 'offline';
    }
  }

  Color _statusColor() {
    if (member.isOnline && member.role != 'restricted' && member.role != 'banned') {
      return accentColor;
    }
    return subColor;
  }

  Widget _buildAvatar() {
    if (member.avatarB64.isNotEmpty) {
      try {
        final bytes = base64Decode(member.avatarB64);
        return CircleAvatar(
          radius: 21,
          backgroundImage: MemoryImage(bytes),
        );
      } catch (_) {}
    }
    final initials = member.displayName.isNotEmpty
        ? member.displayName.substring(0, 1).toUpperCase()
        : '?';
    return CircleAvatar(
      radius: 21,
      backgroundColor: accentColor,
      child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 16)),
    );
  }

  Widget _buildBadge() {
    if (member.role == 'creator' || member.role == 'admin') {
      final label = member.customRank.isNotEmpty ? member.customRank : member.role;
      return Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: accentColor),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final engine = context.read<EngineService>();
    final items = <PopupMenuEntry<String>>[];

    items.add(const PopupMenuItem(value: 'view', child: Text('View Profile')));

    if (tab == _MemberTab.admins || tab == _MemberTab.members) {
      items.add(const PopupMenuItem(value: 'promote', child: Text('Promote to Admin')));
      items.add(const PopupMenuItem(value: 'restrict', child: Text('Restrict User')));
      items.add(PopupMenuItem(
        value: 'remove',
        child: Text('Remove from Group', style: TextStyle(color: Colors.red.shade400)),
      ));
    }
    if (tab == _MemberTab.restricted) {
      items.add(const PopupMenuItem(value: 'restrict', child: Text('Edit Restrictions')));
      items.add(const PopupMenuItem(value: 'unban', child: Text('Remove Restrictions')));
    }
    if (tab == _MemberTab.kicked) {
      items.add(const PopupMenuItem(value: 'unban', child: Text('Unban')));
    }

    if (member.promotedBy.isNotEmpty && member.promotedDate > 0) {
      final dt = DateTime.fromMillisecondsSinceEpoch(member.promotedDate * 1000);
      final dateStr = '${dt.day}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
      final action = tab == _MemberTab.admins ? 'Promoted' : 'Restricted';
      items.add(PopupMenuItem(
        enabled: false,
        child: Text(
          '$action by ${member.promotedBy} on $dateStr',
          style: TextStyle(fontSize: 12, color: subColor),
        ),
      ));
    }

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: items,
      color: isDark ? const Color(0xFF1E2C3A) : Colors.white,
    ).then((action) {
      if (action == null) return;
      switch (action) {
        case 'view':
          if (InfoPanel.pushUserProfileRequest != null) {
            InfoPanel.pushUserProfileRequest!(member);
          }
          break;
        case 'promote':
          showEditAdminBox(
            context,
            accountId: accountId,
            chatId: chatId,
            member: member,
            isChannel: isChannel,
            promotedBy: member.promotedBy,
          ).then((changed) {
            if (changed == true) onRefresh();
          });
          break;
        case 'restrict':
          showEditRestrictedBox(
            context,
            accountId: accountId,
            chatId: chatId,
            member: member,
          ).then((changed) {
            if (changed == true) onRefresh();
          });
          break;
        case 'remove':
          _confirmRemove(context, engine);
          break;
        case 'unban':
          _doUnban(context, engine);
          break;
      }
    });
  }

  void _confirmRemove(BuildContext context, EngineService engine) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove ${member.label} from the group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await engine.removeMember(accountId, chatId, member.userId);
                onRefresh();
              } catch (_) {}
            },
            child: Text('Remove', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    );
  }

  void _doUnban(BuildContext context, EngineService engine) async {
    try {
      await engine.unbanChatMember(accountId, chatId, member.userId);
      onRefresh();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onSecondaryTapDown: (d) => _showContextMenu(context, d.globalPosition),
      onLongPress: () {
        final box = context.findRenderObject() as RenderBox;
        final pos = box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2));
        _showContextMenu(context, pos);
      },
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildAvatar(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            member.label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _buildBadge(),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _statusText(),
                      style: TextStyle(fontSize: 13, color: _statusColor()),
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
}
