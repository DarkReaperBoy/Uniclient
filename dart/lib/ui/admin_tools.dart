import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/telegram_palette.dart';
import 'choose_datetime_box.dart';
import 'create_giveaway_box.dart' show showCreateGiveawayBox;
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
  // Direct-messages (monoforum) current state, for the "Direct Messages" box.
  bool _directMessagesEnabled = false;
  int _directMessagesStars = 0;
  // Star-ref JOIN gating for the channel "Affiliate Program" row.
  bool _starRefJoinAllowed = false;
  bool _adminCanPost = false;
  // Reactions box extras (broadcast EditAllowedReactionsBox).
  int _reactionsUniqMax = 11;
  int _reactionsMaxCount = 0;
  bool _paidReactionsEnabled = false;

  // Channel sub-type & admin capability flags (from GetChatPermissionFlags),
  // mirroring AyuGram ChannelData::* used by edit_peer_info_box fillManageSection.
  bool _isMegagroupFlag = false;
  bool _isBroadcastFlag = false;
  bool _isGigagroupFlag = false;
  bool _amCreator = false;
  bool _hasAdminRights = false;
  bool _adminCanChangeInfo = false;
  bool _canSetStickers = false;
  String _migratedFromChatId = '';

  // Bot manage gating (from GetBotManageInfo + revenue stats).
  bool _botHasVerifierSettings = false;
  bool _botStarRefAllowed = false;
  bool _botHasCurrencyBalance = false;
  bool _botHasCreditsBalance = false;

  bool get _isChannel => widget.chat.type == ChatType.channel;
  bool get _isBot => widget.chat.isBot;
  bool get _isMegagroup => !_isChannel && !_isBot && widget.chat.type == ChatType.group;

  // ── Derived capability getters (1:1 with AyuGram data_channel.cpp) ──
  // NOTE: the engine maps a broadcast channel to ChatType.channel but a
  // SUPERGROUP (megagroup) to ChatType.group, so the Dart `_isChannel` getter
  // is broadcast-only. AyuGram's `isChannel()` means "is a tg.Channel" (broadcast
  // OR supergroup) — captured here by `_isChannelOrSuper` from the loaded flags.
  bool get _isChannelOrSuper => _isBroadcastFlag || _isMegagroupFlag;
  // canEditInformation() for a broadcast = (adminRights & ChangeInfo) || amCreator.
  bool get _canEditInformation => _isBroadcastFlag && (_adminCanChangeInfo || _amCreator);
  // canEditSignatures() = isBroadcast && canEditInformation; box also requires !isMegagroup.
  bool get _canEditSignatures => _isBroadcastFlag && _canEditInformation && !_isMegagroupFlag;
  // canEditAutoTranslate() = isBroadcast && canEditInformation.
  bool get _canEditAutoTranslate => _isBroadcastFlag && _canEditInformation;
  // canViewKicked = isChannel && (isMegagroup ? (isBroadcast || isGigagroup) : true).
  bool get _canViewKicked =>
      _isChannelOrSuper && (_isMegagroupFlag ? (_isBroadcastFlag || _isGigagroupFlag) : true);
  // hasRecentActions = isChannel && (hasAdminRights || amCreator).
  bool get _hasRecentActions => _isChannelOrSuper && (_hasAdminRights || _amCreator);
  // canEditStickers() = (flags & CanSetStickers); box requires isChannel.
  bool get _canEditStickers => _isChannelOrSuper && _canSetStickers;
  // canDelete() = amCreator(); box: canDeleteChannel = isChannel && canDelete().
  bool get _canDeleteChannel => _isChannelOrSuper && _amCreator;
  // canEditColorIndex = isChannel && canEditEmoji(); canEditEmoji() =
  // amCreator() || (adminRights & ChangeInfo) (data_channel.cpp:777). Hidden for
  // legacy basic groups, bots, and members without ChangeInfo.
  bool get _canEditColorIndex => _isChannelOrSuper && (_amCreator || _adminCanChangeInfo);
  // hasStarRef = Join::Allowed(peer) && isChannel && canPostMessages():
  // Join::Allowed for a channel = starref_connect_allowed && isBroadcast &&
  // canPostMessages (info_bot_starref_join_widget.cpp:1083). A channel's only
  // star-ref entry is JOINING other bots' programs, never owning one.
  bool get _canJoinStarRef =>
      _isChannel && _starRefJoinAllowed && (_amCreator || _adminCanPost);

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
    _loadChatFullInfo();
    if (_isBot) _loadBotManageInfo();
  }

  /// Loads bot edit/manage gating info so currency/credits/affiliate/verify rows
  /// only render when applicable (1:1 with AyuGram SlideWrap.toggle gating).
  Future<void> _loadBotManageInfo() async {
    final engine = context.read<EngineService>();
    bool verifier = false;
    bool starRefAllowed = false;
    bool hasCurrency = false;
    bool hasCredits = false;
    try {
      final info = await engine.getBotManageInfo(
        widget.chat.accountId,
        widget.chat.chatId,
      );
      verifier = info['has_verifier_settings'] == true;
      starRefAllowed = info['starref_allowed'] == true;
    } catch (_) {}
    // Balances: the rows stay hidden until a non-zero balance is confirmed.
    try {
      final stats = await engine.getStarsRevenueStats(
        widget.chat.accountId,
        widget.chat.chatId,
      );
      if (stats != null) {
        final current = stats['current_balance'] as int? ?? 0;
        final overall = stats['overall_revenue'] as int? ?? 0;
        hasCredits = current > 0;
        hasCurrency = overall > 0 || current > 0;
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _botHasVerifierSettings = verifier;
        _botStarRefAllowed = starRefAllowed;
        _botHasCurrencyBalance = hasCurrency;
        _botHasCreditsBalance = hasCredits;
      });
    }
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
          _antispamEnabled = flags['antispam'] == true;
          _antispamLoaded = true;
          _isMegagroupFlag = flags['is_megagroup'] == true;
          _isBroadcastFlag = flags['is_broadcast'] == true;
          _isGigagroupFlag = flags['is_gigagroup'] == true;
          _amCreator = flags['am_creator'] == true;
          _hasAdminRights = flags['has_admin_rights'] == true;
          _adminCanChangeInfo = flags['admin_can_change_info'] == true;
          _canSetStickers = flags['can_set_stickers'] == true;
          _migratedFromChatId = (flags['migrated_from_chat_id'] as String?) ?? '';
          _directMessagesEnabled = flags['direct_messages_enabled'] == true;
          _directMessagesStars = (flags['direct_messages_stars'] as num?)?.toInt() ?? 0;
          _starRefJoinAllowed = flags['starref_join_allowed'] == true;
          _adminCanPost = flags['admin_can_post'] == true;
          _reactionsUniqMax = (flags['reactions_uniq_max'] as num?)?.toInt() ?? 11;
          _reactionsMaxCount = (flags['reactions_max_count'] as num?)?.toInt() ?? 0;
          _paidReactionsEnabled = flags['paid_reactions_enabled'] == true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _historyLoaded = true;
          _signMessagesLoaded = true;
          _autoTranslateLoaded = true;
          _antispamLoaded = true;
        });
      }
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
                  // Group sticker set is a channel/supergroup capability
                  // (canEditStickers = isChannel && CanSetStickers), not a
                  // regular-group feature.
                  if (_canEditStickers) ...[
                    Divider(height: 1, color: dividerColor),
                    const SizedBox(height: 6),
                    _buildStickerSection(textColor, subTextColor, accentColor),
                  ],
                  // Delete is only offered when the user can actually delete the
                  // peer: canDeleteChannel = isChannel && canDelete() (amCreator).
                  // AyuGram's deleteWithConfirmation asserts a non-null channel, so
                  // legacy groups, bots and non-creator admins get no Delete row.
                  if (_canDeleteChannel) ...[
                    Divider(height: 1, color: dividerColor),
                    const SizedBox(height: 6),
                    _buildDeleteButton(attentionColor),
                    const SizedBox(height: 12),
                  ],
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
          value: _linkedChatId.isNotEmpty ? 'Linked' : 'Add',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => _showLinkedChatDialog(),
        ),
        if (_canEditColorIndex)
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
        _EditRow(
          icon: Icons.block,
          label: 'Restrict Saving Content',
          value: '',
          textColor: textColor,
          subTextColor: subTextColor,
          isToggle: true,
          toggleValue: _noForwards,
          onTap: () => setState(() => _noForwards = !_noForwards),
        ),
        // Join-to-send / approve-members are megagroup-only (AyuGram gates these
        // on _peer->isMegagroup() in fillPrivacyTypeButton); regular chats and
        // broadcast channels don't expose them.
        if (_isMegagroupFlag) ...[
          _EditRow(
            icon: Icons.login,
            label: 'Members Must Join to Send',
            value: '',
            textColor: textColor,
            subTextColor: subTextColor,
            isToggle: true,
            toggleValue: _joinToSend,
            onTap: () => setState(() => _joinToSend = !_joinToSend),
          ),
          _EditRow(
            icon: Icons.person_add_alt_1,
            label: 'Approve New Members',
            value: '',
            textColor: textColor,
            subTextColor: subTextColor,
            isToggle: true,
            toggleValue: _joinRequest,
            onTap: () => setState(() => _joinRequest = !_joinRequest),
          ),
        ],
        if (_isChannel) ...[
          // canEditAutoTranslate = isBroadcast && canEditInformation.
          if (_canEditAutoTranslate)
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
          // canEditSignatures = isBroadcast && canEditInformation && !isMegagroup.
          if (_canEditSignatures) ...[
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
          ],
          // canEditDirectMessages = isChannel && isBroadcast && canEditInformation
          // (edit_peer_info_box.cpp:1473). Hidden for admins without ChangeInfo.
          if (_canEditInformation)
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

  Future<void> _showBoostRequiredDialog(
    int currentLevel,
    int requiredLevel, {
    String title = 'Enable Auto-Translation',
    IconData icon = Icons.translate,
    String description = '',
  }) async {
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
            Icon(icon, size: 48, color: accentColor),
            const SizedBox(height: 12),
            Text(title,
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
              description.isNotEmpty
                  ? description
                  : 'Your channel needs to reach Level $requiredLevel to enable auto-translation.\n\n'
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
    // Required boost level comes from the server appConfig
    // (channel_autotranslation_level_min), surfaced via GetChatPermissionFlags;
    // it falls back to AyuGram's default of 3 only if unset.
    final minLevel = _autoTranslateMinLevel > 0 ? _autoTranslateMinLevel : 3;
    final enabled = !_autoTranslateDisabled; // current on/off state
    final target = !enabled; // state we are toggling to
    // Enabling auto-translation requires the channel to have reached minLevel.
    if (target && _boostLevel < minLevel) {
      _showBoostRequiredDialog(_boostLevel, minLevel);
      return;
    }
    final engine = context.read<EngineService>();
    setState(() => _autoTranslateDisabled = !target);
    try {
      // Channel-wide admin toggle (channels.toggleAutotranslation) takes the
      // ENABLED state — distinct from the per-user togglePeerTranslations.
      await engine.toggleChannelAutoTranslation(
        widget.chat.accountId,
        widget.chat.chatId,
        target,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _autoTranslateDisabled = target); // revert
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
    // Broadcast-only extras mirroring EditAllowedReactionsBox: a per-message
    // max-count slider (1..reactions_uniq_max) and a paid-reactions toggle. For
    // megagroups AyuGram omits these (they live under `if (!isGroup)`).
    final showBroadcastExtras = _isChannel;
    final maxLimit = _reactionsUniqMax < 1 ? 11 : _reactionsUniqMax;
    int maxCount = _reactionsMaxCount > 0
        ? _reactionsMaxCount.clamp(1, maxLimit)
        : (maxLimit ~/ 2).clamp(1, maxLimit);
    bool paidEnabled = _paidReactionsEnabled;

    final result = await showDialog<(String, List<String>, int, bool)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: bgColor,
          title: Text('Reactions', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  // Max-count slider + paid toggle (broadcast, reactions enabled).
                  if (showBroadcastExtras && mode != 'none') ...[
                    const SizedBox(height: 8),
                    const Divider(),
                    Text('Maximum Reactions',
                        style: TextStyle(color: subTextColor, fontSize: 13)),
                    Row(
                      children: [
                        Text('1', style: TextStyle(color: subTextColor, fontSize: 12)),
                        Expanded(
                          child: Slider(
                            value: maxCount.toDouble(),
                            min: 1,
                            max: maxLimit.toDouble(),
                            divisions: (maxLimit - 1) < 1 ? 1 : (maxLimit - 1),
                            label: '$maxCount',
                            activeColor: accentColor,
                            onChanged: (v) => setDialogState(() => maxCount = v.round()),
                          ),
                        ),
                        Text('$maxLimit', style: TextStyle(color: subTextColor, fontSize: 12)),
                      ],
                    ),
                    Text(
                      'Limit the number of different reactions that can be added to each message.',
                      style: TextStyle(color: subTextColor, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Paid Reactions',
                          style: TextStyle(color: textColor, fontSize: 14)),
                      subtitle: Text('Allow subscribers to send paid Star reactions.',
                          style: TextStyle(color: subTextColor, fontSize: 12)),
                      value: paidEnabled,
                      activeColor: accentColor,
                      onChanged: (v) => setDialogState(() => paidEnabled = v),
                    ),
                  ],
                ],
              ),
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
                Navigator.pop(ctx, (mode, selectedEmojis.toList(), maxCount, paidEnabled));
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
        maxCount: showBroadcastExtras ? result.$3 : 0,
        paidEnabled: showBroadcastExtras ? result.$4 : false,
      );
      if (mounted) {
        setState(() {
          _reactionsMaxCount = result.$3;
          _paidReactionsEnabled = result.$4;
        });
        showTelegramToast(context, 'Reactions updated');
      }
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

    Map<String, dynamic> fullInfo = {};
    try {
      fullInfo = await engine.getFullChatInfo(widget.chat.accountId, widget.chat.chatId);
    } catch (_) {}

    final currentColorId = fullInfo['peer_color_id'] as int? ?? -1;
    final currentStatusId = (fullInfo['emoji_status_id'] as int?) ?? 0;
    final currentBgEmojiId = (fullInfo['background_emoji_id'] as int?) ?? 0;

    // Pre-load the custom-emoji pool + thumbnails so the dialog shows a real
    // visual picker instead of asking the user to type document IDs. Mirrors
    // AyuGram's edit_peer_color_box EmojiListWidget / EmojiStatusPanel
    // (edit_peer_color_box.cpp:747) — the user can never know numeric IDs.
    List<int> emojiIds = [];
    Map<int, CustomEmojiThumbData> emojiThumbs = {};
    try {
      emojiIds = await engine.getBackgroundEmojiList(widget.chat.accountId);
      if (emojiIds.isNotEmpty) {
        emojiThumbs = await engine.getCustomEmojiThumbs(
            widget.chat.accountId, emojiIds.take(60).toList());
      }
    } catch (_) {}
    if (!mounted) return;
    // Ensure the currently-set emoji is selectable even if outside the pool.
    final pickIds = <int>[
      if (currentStatusId != 0 && !emojiIds.contains(currentStatusId)) currentStatusId,
      if (currentBgEmojiId != 0 && !emojiIds.contains(currentBgEmojiId)) currentBgEmojiId,
      ...emojiIds,
    ];

    final result = await showDialog<(int, int, int)?>(
      context: context,
      builder: (ctx) {
        int selectedColor = currentColorId;
        int selectedStatus = currentStatusId;
        int selectedBgEmoji = currentBgEmojiId;

        Widget emojiPicker(int selectedId, ValueChanged<int> onPick) {
          return SizedBox(
            height: 132,
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  // "Off" chip — clears the emoji (AyuGram's no-emoji option).
                  GestureDetector(
                    onTap: () => onPick(0),
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: selectedId == 0
                            ? Border.all(color: accentColor, width: 2)
                            : Border.all(color: subTextColor.withValues(alpha: 0.3)),
                      ),
                      child: Icon(Icons.block, size: 18, color: subTextColor),
                    ),
                  ),
                  ...pickIds.map((id) {
                    final isSel = id == selectedId;
                    final b64 = emojiThumbs[id]?.thumbB64 ?? '';
                    return GestureDetector(
                      onTap: () => onPick(id),
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: isSel ? accentColor.withValues(alpha: 0.1) : null,
                          border: isSel ? Border.all(color: accentColor, width: 2) : null,
                        ),
                        child: b64.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.memory(
                                  base64Decode(b64),
                                  width: 28,
                                  height: 28,
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
                                  errorBuilder: (_, __, ___) =>
                                      Icon(Icons.emoji_emotions_outlined, size: 20, color: subTextColor),
                                ),
                              )
                            : Icon(Icons.emoji_emotions_outlined, size: 20, color: subTextColor),
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        }

        return StatefulBuilder(
          builder: (ctx, setLocalState) => AlertDialog(
            backgroundColor: bgColor,
            title: Text('Color & Emoji', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),
            content: SizedBox(
              width: 300,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Name Color', style: TextStyle(color: subTextColor, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: colors.map((c) {
                        final color = c.dayColors.isNotEmpty
                            ? Color(0xFF000000 | c.dayColors.first)
                            : const Color(0xFF999999);
                        final isSelected = c.colorId == selectedColor;
                        return GestureDetector(
                          onTap: () => setLocalState(() => selectedColor = c.colorId),
                          child: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color,
                              border: isSelected
                                  ? Border.all(color: accentColor, width: 2.5)
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Text('Emoji Status', style: TextStyle(color: subTextColor, fontSize: 13)),
                    const SizedBox(height: 6),
                    if (pickIds.isEmpty)
                      Text('No custom emoji available',
                          style: TextStyle(color: subTextColor.withValues(alpha: 0.6), fontSize: 12))
                    else
                      emojiPicker(selectedStatus, (id) => setLocalState(() => selectedStatus = id)),
                    const SizedBox(height: 14),
                    Text('Background Emoji', style: TextStyle(color: subTextColor, fontSize: 13)),
                    const SizedBox(height: 6),
                    if (pickIds.isEmpty)
                      Text('No custom emoji available',
                          style: TextStyle(color: subTextColor.withValues(alpha: 0.6), fontSize: 12))
                    else
                      emojiPicker(selectedBgEmoji, (id) => setLocalState(() => selectedBgEmoji = id)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: subTextColor))),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx, (selectedColor, selectedStatus, selectedBgEmoji));
                },
                child: Text('Save', style: TextStyle(color: accentColor, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        );
      },
    );
    if (result == null || !mounted) return;
    final (colorId, statusId, bgEmojiId) = result;

    final colorChanged = colorId != currentColorId;
    final bgChanged = bgEmojiId != currentBgEmojiId;
    final statusChanged = statusId != currentStatusId;
    // Nothing changed → close without a server round-trip (AyuGram's close()).
    if (!colorChanged && !bgChanged && !statusChanged) return;

    // Pre-flight boost-level check for non-self peers: prompt to boost instead of
    // letting updateChannelColor fail server-side (edit_peer_color_box.cpp:666).
    try {
      final req = await engine.getColorLevelRequirements(widget.chat.accountId);
      if (!mounted) return;
      if (req.isNotEmpty) {
        final levels = (req[_isMegagroupFlag ? 'group_levels' : 'channel_levels']
            as Map<String, dynamic>?) ?? const {};
        final bgIconMin = (req['bg_icon_level_min'] as num?)?.toInt() ?? 0;
        final statusMin = (req['emoji_status_level_min'] as num?)?.toInt() ?? 0;
        final colorRequired = colorId >= 0 ? ((levels['$colorId'] as num?)?.toInt() ?? 0) : 0;
        final iconRequired = bgEmojiId != 0 ? bgIconMin : 0;
        final statusRequired = (statusChanged && statusId != 0) ? statusMin : 0;
        final required = [colorRequired, iconRequired, statusRequired]
            .reduce((a, b) => a > b ? a : b);
        if (_boostLevel < required) {
          _showBoostRequiredDialog(
            _boostLevel,
            required,
            title: 'Boost to Change Appearance',
            icon: Icons.palette_outlined,
            description:
                'Your ${_isChannel ? "channel" : "group"} needs to reach Level $required '
                'to use this color & emoji.\n\n'
                'Ask ${_isChannel ? "subscribers" : "members"} to boost.',
          );
          return;
        }
      }
    } catch (_) {
      // Couldn't determine requirements — fall through and let the save attempt
      // surface any server-side error as before.
    }

    try {
      if (colorId >= 0) {
        await engine.updateChannelColor(widget.chat.accountId, widget.chat.chatId, colorId,
          backgroundEmojiId: bgEmojiId, statusEmojiId: statusId);
      }
      if (mounted) showTelegramToast(context, 'Color & emoji updated');
    } catch (e) {
      if (mounted) showTelegramToast(context, 'Failed: $e');
    }
  }

  Future<void> _showDirectMessagesDialog(Color textColor, Color subTextColor, Color accentColor) async {
    final engine = context.read<EngineService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final priceCtrl = TextEditingController(
      text: _directMessagesStars > 0 ? '$_directMessagesStars' : '',
    );

    // AyuGram's EditDirectMessagesPriceBox: an "Allow direct messages" toggle
    // that, when off, sends a disabled value (no broadcast_messages_allowed flag);
    // when on, the per-message Stars price (0 = free but still enabled)
    // (edit_privacy_box.cpp:1314).
    final result = await showDialog<(bool, int)>(
      context: context,
      builder: (ctx) {
        bool allow = _directMessagesEnabled;
        return StatefulBuilder(
          builder: (ctx, setLocalState) => AlertDialog(
            backgroundColor: bgColor,
            title: Text('Direct Messages', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Allow direct messages',
                      style: TextStyle(color: textColor, fontSize: 14)),
                  value: allow,
                  activeColor: accentColor,
                  onChanged: (v) => setLocalState(() => allow = v),
                ),
                if (allow) ...[
                  const SizedBox(height: 4),
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
                ] else
                  Text(
                    'Subscribers will not be able to send direct messages to this channel.',
                    style: TextStyle(color: subTextColor, fontSize: 13),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: subTextColor))),
              TextButton(
                onPressed: () => Navigator.pop(ctx, (allow, int.tryParse(priceCtrl.text) ?? 0)),
                child: Text('Save', style: TextStyle(color: accentColor, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      },
    );
    if (result == null || !mounted) return;
    final (allow, price) = result;
    try {
      await engine.updatePaidMessagesPrice(
        widget.chat.accountId,
        widget.chat.chatId,
        allow ? price : 0,
        broadcastEnabled: allow,
      );
      if (mounted) {
        setState(() {
          _directMessagesEnabled = allow;
          _directMessagesStars = allow ? price : 0;
        });
        showTelegramToast(context, allow ? 'Direct messages updated' : 'Direct messages disabled');
      }
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
            // lng_manage_peer_bot_public_link = "Public Link" (single username).
            label: 'Public Link',
            value: '',
            textColor: textColor,
            subTextColor: subTextColor,
            onTap: () => _showBotPublicLink(textColor, subTextColor),
          ),
        // Currency/Credits rows stay hidden until a non-zero balance is confirmed
        // (AyuGram wraps them in SlideWrap.toggle(!balance.isEmpty())).
        if (_botHasCurrencyBalance)
          _EditRow(
            icon: Icons.monetization_on_outlined,
            label: 'Currency Balance',
            value: '',
            textColor: textColor,
            subTextColor: subTextColor,
            onTap: () => _showRevenueStats(textColor, subTextColor, isCurrency: true),
          ),
        if (_botHasCreditsBalance)
          _EditRow(
            icon: Icons.stars_outlined,
            label: 'Credits Balance',
            value: '',
            textColor: textColor,
            subTextColor: subTextColor,
            onTap: () => _showRevenueStats(textColor, subTextColor, isCurrency: false),
          ),
        // Affiliate (star-ref) setup is gated by the server appConfig
        // (Info::BotStarRef::Setup::Allowed → starref_program_allowed).
        if (_botStarRefAllowed)
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
        // Verify Accounts is only available when the bot actually has verifier
        // settings (AyuGram fillBotVerifyAccounts gates on botInfo->verifierSettings).
        if (_botHasVerifierSettings)
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

  // AyuGram's fillBotUsernamesButton opens UsernamesBox (edit_peer_info_box.cpp:1786).
  // Editing/reordering a bot's usernames goes through the bots.* API, which the
  // engine bridge doesn't expose for users (BotsToggleUsername is "Skipped" in
  // dispatch_gen.go). For the common single-username bot this matches AyuGram's
  // box: it shows the public link with copy/open actions.
  Future<void> _showBotPublicLink(Color textColor, Color subTextColor) async {
    final engine = context.read<EngineService>();
    String username = widget.chat.username;
    try {
      final fetched = await engine.getChatUsername(widget.chat.accountId, widget.chat.chatId);
      if (fetched.isNotEmpty) username = fetched;
    } catch (_) {}
    if (!mounted || username.isEmpty) return;
    final link = 'https://t.me/$username';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final accentColor = PaletteProvider.of(context).windowBgActive;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('Public Link', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'People can find your bot by this link and start it.',
              style: TextStyle(color: subTextColor, fontSize: 13),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: link));
                showTelegramToast(ctx, 'Link copied');
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        't.me/$username',
                        style: TextStyle(color: accentColor, fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ),
                    Icon(Icons.copy, size: 18, color: accentColor),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              showTelegramToast(ctx, 'Link copied');
            },
            child: Text('Copy', style: TextStyle(color: accentColor)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: TextStyle(color: subTextColor)),
          ),
        ],
      ),
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

    Map<String, dynamic>? stats;
    try {
      stats = await engine.getStarsRevenueStats(
        widget.chat.accountId,
        widget.chat.chatId,
      );
    } catch (e) {
      if (mounted) showTelegramToast(context, 'Failed to load stats: $e');
      return;
    }
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
    final existingCommission = affiliateInfo['commission_permille'] as int? ?? 0;
    final existingDuration = affiliateInfo['duration_months'] as int? ?? 0;

    final commissionCtrl = TextEditingController(
      text: hasProgram ? '${(existingCommission / 10).toStringAsFixed(1)}' : '',
    );
    final durationValues = [0, 1, 3, 6, 12, 24, 36];
    final durationLabels = ['Lifetime', '1 month', '3 months', '6 months', '1 year', '2 years', '3 years'];

    final result = await showDialog<(double, int)?>(
      context: context,
      builder: (ctx) {
        int selectedDurationIdx = durationValues.indexOf(existingDuration);
        if (selectedDurationIdx < 0) selectedDurationIdx = 0;
        return StatefulBuilder(
          builder: (ctx, setLocalState) => AlertDialog(
            backgroundColor: bgColor,
            title: Text(
              hasProgram ? 'Edit Affiliate Program' : 'Create Affiliate Program',
              style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasProgram) ...[
                  Text('Current: ${(existingCommission / 10).toStringAsFixed(1)}% commission, '
                       '${existingDuration == 0 ? "lifetime" : "$existingDuration months"}',
                    style: TextStyle(color: subTextColor, fontSize: 13)),
                  const SizedBox(height: 12),
                ],
                Text('Commission (%)', style: TextStyle(color: subTextColor, fontSize: 13)),
                const SizedBox(height: 4),
                TextField(
                  controller: commissionCtrl,
                  style: TextStyle(color: textColor, fontSize: 14),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: 'e.g. 20.0',
                    hintStyle: TextStyle(color: subTextColor.withValues(alpha: 0.5)),
                    isDense: true,
                    border: const UnderlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Duration', style: TextStyle(color: subTextColor, fontSize: 13)),
                const SizedBox(height: 4),
                ...List.generate(durationValues.length, (i) {
                  return InkWell(
                    onTap: () => setLocalState(() => selectedDurationIdx = i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            selectedDurationIdx == i ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                            size: 20,
                            color: selectedDurationIdx == i ? accentColor : subTextColor,
                          ),
                          const SizedBox(width: 8),
                          Text(durationLabels[i], style: TextStyle(color: textColor, fontSize: 14)),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: TextStyle(color: subTextColor)),
              ),
              TextButton(
                onPressed: () {
                  final pct = double.tryParse(commissionCtrl.text.trim()) ?? 0;
                  if (pct <= 0 || pct > 100) {
                    showTelegramToast(ctx, 'Commission must be between 0.1% and 100%');
                    return;
                  }
                  Navigator.pop(ctx, (pct, durationValues[selectedDurationIdx]));
                },
                child: Text('Save', style: TextStyle(color: accentColor, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        );
      },
    );
    commissionCtrl.dispose();
    if (result == null || !mounted) return;
    final (commissionPct, durationMonths) = result;
    final commissionPermille = (commissionPct * 10).round();
    try {
      await engine.setStarRefProgram(
        widget.chat.accountId,
        widget.chat.chatId,
        commissionPermille: commissionPermille,
        durationMonths: durationMonths,
      );
      if (mounted) showTelegramToast(context, 'Affiliate program updated');
    } catch (e) {
      if (mounted) showTelegramToast(context, 'Failed: $e');
    }
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
        // Real per-bot verify state, lazily fetched per visible row and cached
        // from UserFull.bot_verification.bot_id (verify_peers_box.cpp:92). A
        // userId absent from the map is still loading.
        final verifyCache = <String, bool>{};
        final pending = <String>{};
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            void ensureState(String userId) {
              if (verifyCache.containsKey(userId) || pending.contains(userId)) return;
              pending.add(userId);
              engine
                  .getBotVerifyState(widget.chat.accountId, widget.chat.chatId, userId)
                  .then((v) {
                pending.remove(userId);
                if (ctx.mounted) setDialogState(() => verifyCache[userId] = v);
              }).catchError((_) {
                pending.remove(userId);
                if (ctx.mounted) setDialogState(() => verifyCache[userId] = false);
              });
            }
            return AlertDialog(
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
                              // Kick off the real per-bot state fetch for this
                              // (visible) row; reflect it once known.
                              ensureState(c.userId);
                              final known = verifyCache.containsKey(c.userId);
                              final verified = verifyCache[c.userId] ?? false;
                              return ListTile(
                                dense: true,
                                leading: !known
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: Padding(
                                          padding: EdgeInsets.all(2),
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      )
                                    : Icon(
                                        verified ? Icons.verified : Icons.person_outline,
                                        color: verified ? accentColor : subTextColor,
                                        size: 20,
                                      ),
                                title: Text(
                                  c.displayName.isNotEmpty ? c.displayName : c.username.isNotEmpty ? '@${c.username}' : c.userId,
                                  style: TextStyle(color: textColor, fontSize: 14),
                                ),
                                subtitle: c.username.isNotEmpty
                                    ? Text('@${c.username}', style: TextStyle(color: subTextColor, fontSize: 12))
                                    : null,
                                // Disabled until the real state is known, so the
                                // tap sends the correct Setup vs Remove action.
                                onTap: !known
                                    ? null
                                    : () async {
                                        try {
                                          await engine.callGeneric(
                                            widget.chat.accountId,
                                            'BotsSetCustomVerification',
                                            {
                                              'bot_id': widget.chat.chatId,
                                              'peer_id': c.userId,
                                              'enabled': !verified,
                                            },
                                          );
                                          if (ctx.mounted) {
                                            setDialogState(() => verifyCache[c.userId] = !verified);
                                            showTelegramToast(ctx, verified ? 'Verification removed' : 'Verification added');
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
          );
          },
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
            // Charge-stars is a channel/supergroup paid-messages feature — never
            // a legacy basic group (gotd 0.143 lacks the paidMessagesAvailable flag).
            paidMessagesPossible: _isChannelOrSuper,
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
        // A channel's Affiliate Program row opens the JOIN flow (advertising
        // other bots' programs), gated on Join::Allowed. The create-your-own
        // SETUP flow is bot-only and would error server-side for a channel.
        if (_canJoinStarRef)
          _EditRow(
            icon: Icons.handshake_outlined,
            label: 'Affiliate Program',
            value: '',
            textColor: textColor,
            subTextColor: subTextColor,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _StarRefJoinScreen(
                accountId: widget.chat.accountId,
                chatId: widget.chat.chatId,
                title: widget.chat.title,
              ),
            )),
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
            isForum: widget.chat.isForum,
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
            isForum: widget.chat.isForum,
            initialTab: _MemberTab.members,
          ),
        ),
        // canViewKicked = isChannel && (isMegagroup ? (isBroadcast||isGigagroup) : true):
        // plain megagroups cannot show a removed-users list.
        if (_canViewKicked)
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
              isForum: widget.chat.isForum,
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
              isForum: widget.chat.isForum,
              initialTab: _MemberTab.requests,
            ),
          ),
        // hasRecentActions = isChannel && (hasAdminRights || amCreator): the admin
        // log is only visible to admins/creators.
        if (_hasRecentActions)
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
        _EditRow(
          icon: Icons.bar_chart,
          label: 'Statistics',
          value: '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => _showStatisticsScreen(),
        ),
        _EditRow(
          icon: Icons.rocket_launch_outlined,
          label: 'Boosts',
          value: '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => _showBoostsScreen(textColor, subTextColor),
        ),
        if (_isChannel)
          _EditRow(
            icon: Icons.monetization_on_outlined,
            label: 'Monetization',
            value: '',
            textColor: textColor,
            subTextColor: subTextColor,
            onTap: () => _showMonetizationScreen(textColor, subTextColor),
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

  void _showStatisticsScreen() {
    // AyuGram navigates to a full Info::ChannelStatistics section page (charts,
    // growth graphs, overview counters, recent posts) — not a flat dialog.
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _StatisticsScreen(
        accountId: widget.chat.accountId,
        chatId: widget.chat.chatId,
        title: widget.chat.title,
        isBroadcast: _isChannel,
      ),
    ));
  }

  void _showBoostsScreen(Color textColor, Color subTextColor) {
    // AyuGram navigates to a full Info::Boosts section page with the level
    // header, progress, premium-audience breakdown and the boosters list.
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _BoostsScreen(
        accountId: widget.chat.accountId,
        chatId: widget.chat.chatId,
        title: widget.chat.title,
      ),
    ));
  }

  void _showMonetizationScreen(Color textColor, Color subTextColor) {
    // AyuGram navigates to a full Channel Earn section (Info::ChannelEarn) with
    // the Stars balance overview rather than a flat key:value dump.
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _MonetizationScreen(
        accountId: widget.chat.accountId,
        chatId: widget.chat.chatId,
        title: widget.chat.title,
      ),
    ));
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
    final engine = context.read<EngineService>();
    final searchCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            return AlertDialog(
              backgroundColor: bgColor,
              title: Text(
                'Group Sticker Set',
                style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600),
              ),
              content: SizedBox(
                width: 320,
                height: 350,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: searchCtrl,
                      style: TextStyle(color: textColor, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search or paste sticker set link',
                        hintStyle: TextStyle(color: subTextColor),
                        prefixIcon: Icon(Icons.search, color: subTextColor, size: 20),
                        isDense: true,
                        border: const UnderlineInputBorder(),
                      ),
                      onSubmitted: (val) async {
                        final shortName = val.trim()
                            .replaceAll(RegExp(r'https?://t\.me/addstickers/'), '')
                            .replaceAll(RegExp(r'https?://telegram\.me/addstickers/'), '')
                            .trim();
                        if (shortName.isEmpty) return;
                        Navigator.pop(ctx);
                        try {
                          await engine.setGroupStickerSet(
                            widget.chat.accountId, widget.chat.chatId, shortName);
                          if (mounted) showTelegramToast(context, 'Sticker set applied');
                        } catch (e) {
                          if (mounted) showTelegramToast(context, 'Failed: $e');
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Text('Your Sticker Sets', style: TextStyle(color: subTextColor, fontSize: 12)),
                    const SizedBox(height: 4),
                    Expanded(
                      child: FutureBuilder<List<StickerPackSummary>>(
                        future: engine.getInstalledStickerPacks(widget.chat.accountId),
                        builder: (ctx, snap) {
                          if (snap.connectionState != ConnectionState.done) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (snap.hasError || !snap.hasData || snap.data!.isEmpty) {
                            return Center(child: Text('No sticker sets found.',
                                style: TextStyle(color: subTextColor, fontSize: 13)));
                          }
                          final packs = snap.data!;
                          return ListView.builder(
                            itemCount: packs.length,
                            itemBuilder: (ctx, i) {
                              final pack = packs[i];
                              return InkWell(
                                onTap: () async {
                                  Navigator.pop(ctx);
                                  try {
                                    await engine.setGroupStickerSet(
                                      widget.chat.accountId, widget.chat.chatId, pack.shortName);
                                    if (mounted) showTelegramToast(context, 'Sticker set "${pack.title}" applied');
                                  } catch (e) {
                                    if (mounted) showTelegramToast(context, 'Failed: $e');
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36, height: 36,
                                        decoration: BoxDecoration(
                                          color: accentColor.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Center(
                                          child: Text(
                                            pack.count > 0 ? '${pack.count}' : '?',
                                            style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(pack.title,
                                                style: TextStyle(color: textColor, fontSize: 14),
                                                maxLines: 1, overflow: TextOverflow.ellipsis),
                                            Text('${pack.count} stickers',
                                                style: TextStyle(color: subTextColor, fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
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
                  child: Text('Cancel', style: TextStyle(color: subTextColor)),
                ),
              ],
            );
          },
        );
      },
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
              // Also delete the migrated-from legacy chat, matching AyuGram's
              // deleteChannel() which removes channel->migrateFrom() via
              // deleteConversation when non-null — otherwise it is orphaned.
              if (_migratedFromChatId.isNotEmpty) {
                engine.deleteChat(widget.chat.accountId, _migratedFromChatId);
              }
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
        isPublic: _hasPublicUsername,
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
  // AyuGram only builds the "Charge Stars for Messages" section when
  // `channel && channel->paidMessagesAvailable()` — i.e. a real channel/
  // supergroup, never a legacy basic group (edit_peer_permissions_box.cpp:1177).
  bool paidMessagesPossible = false,
}) {
  return showDialog(
    context: context,
    builder: (ctx) => _EditPeerPermissionsBox(
      accountId: accountId,
      chatId: chatId,
      isChannel: isChannel,
      isForum: isForum,
      memberCount: memberCount,
      paidMessagesPossible: paidMessagesPossible,
    ),
  );
}

class _PermFlag {
  final String key;
  final String label;
  bool banned;
  // Always-disabled flags (rendered but never editable), mirroring AyuGram's
  // `disabledMessages` lock for EditRank in CreateEditRestrictions.
  final bool locked;

  _PermFlag({required this.key, required this.label, this.banned = false, this.locked = false});
}

class _EditPeerPermissionsBox extends StatefulWidget {
  final String accountId;
  final String chatId;
  final bool isChannel;
  final bool isForum;
  final int memberCount;
  final bool paidMessagesPossible;

  const _EditPeerPermissionsBox({
    required this.accountId,
    required this.chatId,
    required this.isChannel,
    required this.isForum,
    required this.memberCount,
    required this.paidMessagesPossible,
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
  late final TextEditingController _chargeStarsCtrl;
  String? _error;

  late AnimationController _expandCtrl;
  late Animation<double> _expandAnim;

  static const _slowmodeValues = [0, 5, 10, 30, 60, 300, 900, 3600];
  static const _slowmodeLabels = ['Off', '5s', '10s', '30s', '1m', '5m', '15m', '1h'];
  static const _kDefaultChargeStars = 10;

  late final _PermFlag _sendPlain;
  late final List<_PermFlag> _mediaFlags;
  late final List<_PermFlag> _otherFlags;

  List<_PermFlag> get _allFlags => [_sendPlain, ..._mediaFlags, ..._otherFlags];

  @override
  void initState() {
    super.initState();
    _chargeStarsCtrl = TextEditingController(text: '0');
    _expandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _expandAnim = CurvedAnimation(parent: _expandCtrl, curve: Curves.easeOutCubic);
    _sendPlain = _PermFlag(key: 'send_plain', label: 'Send text messages');
    // AyuGram nests a single combined "Stickers & GIFs" permission
    // (SendStickers|SendGifs|SendGames|SendInline → lng_rights_chat_stickers)
    // plus Embed links / Send polls inside the "Send media" group — 9 rows.
    // The Go DefaultBannedRights collapses gifs/games/inline onto send_stickers
    // (telegram.go:16259-16262), so one `send_stickers` flag drives all four.
    _mediaFlags = [
      _PermFlag(key: 'send_photos', label: 'Send photos'),
      _PermFlag(key: 'send_videos', label: 'Send videos'),
      _PermFlag(key: 'send_roundvideos', label: 'Send video messages'),
      _PermFlag(key: 'send_audios', label: 'Send music'),
      _PermFlag(key: 'send_voices', label: 'Send voice messages'),
      _PermFlag(key: 'send_docs', label: 'Send files'),
      _PermFlag(key: 'send_stickers', label: 'Stickers & GIFs'),
      _PermFlag(key: 'embed_links', label: 'Send links'),
      _PermFlag(key: 'send_polls', label: 'Send polls'),
    ];
    _otherFlags = [
      _PermFlag(key: 'invite_users', label: 'Add members'),
      if (widget.isForum) _PermFlag(key: 'manage_topics', label: 'Create topics'),
      _PermFlag(key: 'pin_messages', label: 'Pin messages'),
      // EditRank is rendered but always locked (NestedRestrictionLabelsList →
      // disabledMessages); lng_rights_group_edit_rank = "Edit own tags".
      _PermFlag(key: 'edit_rank', label: 'Edit own tags', locked: true),
      _PermFlag(key: 'change_info', label: 'Change group info'),
    ];
    _loadRights();
  }

  @override
  void dispose() {
    _chargeStarsCtrl.dispose();
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
        _chargeStarsCtrl.text = '$_chargeStars';
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
      // AyuGram only persists a non-zero boosts threshold when send-restrictions
      // or slow mode are actually active; otherwise it writes 0 so a stale
      // threshold can't apply with nothing to bypass (edit_peer_permissions_box.cpp:1259-1263).
      await engine.setBoostsUnrestrict(
        widget.accountId, widget.chatId, _boostsSectionVisible ? _boostsUnrestrict : 0);
      if (widget.paidMessagesPossible) {
        await engine.updatePaidMessagesPrice(
          widget.accountId, widget.chatId, _chargeStars,
          broadcastEnabled: widget.isChannel && _chargeStars > 0,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showTelegramToast(context, 'Failed: $e');
      }
    }
  }

  void _toggleFlag(_PermFlag flag) {
    if (flag.locked) return;
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

  // kSendRestrictions (edit_peer_permissions_box.cpp:1211-1223): the text/media/
  // embed/poll send flags. _otherFlags (invite/topics/pin/rank/change_info) are
  // NOT send restrictions. Boosts-to-unrestrict only applies when sending is
  // actually restricted (or slow mode is on).
  bool get _hasSendRestrictions =>
      _sendPlain.banned || _mediaFlags.any((f) => f.banned);

  bool get _boostsSectionVisible =>
      _hasSendRestrictions || _slowmodeValues[_slowmodeIndex] > 0;

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
                    // Boosts-to-unrestrict is only shown when there are send
                    // restrictions or slow mode (AddBoostsUnrestrictWrapped gated
                    // on hasSendRestrictions; edit_peer_permissions_box.cpp:1226-1229).
                    if (_boostsSectionVisible) ...[
                      Divider(height: 1, color: dividerColor),
                      const SizedBox(height: 12),
                      _buildBoostsSection(accentColor, textColor, subTextColor),
                    ],
                    if (widget.paidMessagesPossible) ...[
                      Divider(height: 1, color: dividerColor),
                      const SizedBox(height: 12),
                      _buildSectionHeader('Charge Stars', headerColor),
                      const SizedBox(height: 4),
                      _buildChargeStarsSection(accentColor, textColor, subTextColor),
                    ],
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
    final dependencyLocked = flag.key == 'embed_links' && _sendPlain.banned;
    final isLocked = flag.locked || dependencyLocked;

    return InkWell(
      onTap: () {
        if (flag.locked) {
          showTelegramToast(context, 'You cannot change this permission.');
          return;
        }
        if (dependencyLocked) {
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

  Widget _buildBoostsSection(Color accentColor, Color textColor, Color subTextColor) {
    final enabled = _boostsUnrestrict > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The "off" state is a separate toggle in AyuGram
        // (lng_rights_boosts_no_restrict); the slider only appears when it is on
        // (edit_peer_permissions_box.cpp:961-995).
        InkWell(
          onTap: () => setState(() => _boostsUnrestrict = enabled ? 0 : 1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Do not restrict boosters',
                    style: TextStyle(fontSize: 14, color: textColor),
                  ),
                ),
                const SizedBox(width: 20),
                SizedBox(
                  height: 24,
                  child: Switch(
                    value: enabled,
                    onChanged: (val) => setState(() => _boostsUnrestrict = val ? 1 : 0),
                    activeColor: accentColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (enabled) ...[
          const SizedBox(height: 4),
          _buildBoostsSlider(accentColor, textColor, subTextColor),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
          child: Text(
            // lng_rights_boosts_about_on / lng_rights_boosts_about.
            enabled
                ? 'Choose how many boosts a user must give to the group to bypass restrictions on sending messages.'
                : 'Turn this on to always allow users who boosted your group to send messages and media.',
            style: TextStyle(fontSize: 12, color: subTextColor),
          ),
        ),
      ],
    );
  }

  Widget _buildBoostsSlider(Color accentColor, Color textColor, Color subTextColor) {
    // 5 positions, values 1..5 (BoostsUnrestrictByIndex(i) = i + 1,
    // kBoostsUnrestrictValues = 5; edit_peer_permissions_box.cpp:54,207).
    final idx = _boostsUnrestrict.clamp(1, 5) - 1;
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
              value: idx.toDouble(),
              min: 0,
              max: 4,
              divisions: 4,
              onChanged: (v) => setState(() => _boostsUnrestrict = v.round() + 1),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (int i = 0; i < 5; i++)
                  Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 10,
                      color: i == idx ? textColor : subTextColor,
                      fontWeight: i == idx ? FontWeight.w600 : FontWeight.normal,
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
                    onChanged: (val) => setState(() {
                      _chargeStars = val ? _kDefaultChargeStars : 0;
                      _chargeStarsCtrl.text = '$_chargeStars';
                    }),
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
                      controller: _chargeStarsCtrl,
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
                          setState(() => _chargeStars = parsed);
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
          isForum: widget.isForum,
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
  bool _pickingDate = false;

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
    // Same nested "Send media" group as the permissions box: a single combined
    // "Stickers & GIFs" plus Embed links / Send polls live INSIDE the media
    // group (NestedRestrictionLabelsList, edit_peer_permissions_box.cpp:81-94).
    _mediaFlags = [
      _PermFlag(key: 'send_photos', label: 'Send photos'),
      _PermFlag(key: 'send_videos', label: 'Send videos'),
      _PermFlag(key: 'send_roundvideos', label: 'Send video messages'),
      _PermFlag(key: 'send_audios', label: 'Send music'),
      _PermFlag(key: 'send_voices', label: 'Send voice messages'),
      _PermFlag(key: 'send_docs', label: 'Send files'),
      _PermFlag(key: 'send_stickers', label: 'Stickers & GIFs'),
      _PermFlag(key: 'embed_links', label: 'Send links'),
      _PermFlag(key: 'send_polls', label: 'Send polls'),
    ];
    _otherFlags = [
      _PermFlag(key: 'invite_users', label: 'Add members'),
      if (widget.isForum) _PermFlag(key: 'manage_topics', label: 'Create topics'),
      _PermFlag(key: 'pin_messages', label: 'Pin messages'),
      // EditRank: user-specific restriction box → lng_rights_group_edit_rank_single
      // = "Edit own tag"; always locked.
      _PermFlag(key: 'edit_rank', label: 'Edit own tag', locked: true),
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
      int bannedUntil = 0;
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
          bannedUntil = (info['banned_until'] as num?)?.toInt() ?? 0;
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
        // Seed the "Banned until" selector from the member's existing expiry
        // (AyuGram: _until = prepareRights.until; createUntilVariants adds the
        // current expiry as a radio). 0 / INT_MAX (2147483647) = forever.
        if (bannedUntil > 0 && bannedUntil != 2147483647) {
          _customDate = DateTime.fromMillisecondsSinceEpoch(bannedUntil * 1000);
          _duration = _BanDuration.custom;
        } else {
          _duration = _BanDuration.forever;
          _customDate = null;
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
    if (flag.locked) return;
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

  // Selecting a duration. "Custom" opens the picker WITHOUT committing the
  // radio first — it commits only on a successful pick and reverts on cancel,
  // so a dismissed picker can't silently collapse the ban to "forever".
  void _selectDuration(_BanDuration value) {
    if (value == _BanDuration.custom) {
      _pickCustomDate();
    } else {
      setState(() => _duration = value);
    }
  }

  Future<void> _pickCustomDate() async {
    if (_pickingDate) return;
    _pickingDate = true;
    // Remember the current selection so we can revert if the picker is
    // cancelled — AyuGram resets the radio group back to _until when
    // ChooseDateTimeBox is dismissed (edit_participant_box.cpp:1019-1022).
    final previousDuration = _duration;
    final previousCustom = _customDate;
    try {
      final now = DateTime.now();
      final maxDate = now.add(const Duration(days: _kMaxRestrictDelayDays));
      var initial = _customDate ?? now.add(const Duration(days: 1));
      if (initial.isBefore(now)) initial = now.add(const Duration(days: 1));
      final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: now,
        lastDate: maxDate,
      );
      if (picked == null) {
        if (mounted) {
          setState(() {
            _duration = previousDuration;
            _customDate = previousCustom;
          });
        }
        return;
      }
      if (!mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_customDate ?? now.add(const Duration(days: 1))),
      );
      if (!mounted) return;
      if (time == null) {
        setState(() {
          _duration = previousDuration;
          _customDate = previousCustom;
        });
        return;
      }
      var chosen = DateTime(picked.year, picked.month, picked.day, time.hour, time.minute);
      // ChooseDateTimeBox enforces min = now (edit_participant_box.cpp:996).
      if (!chosen.isAfter(now)) {
        chosen = now.add(const Duration(minutes: 1));
      }
      setState(() {
        _customDate = chosen;
        _duration = _BanDuration.custom;
      });
    } finally {
      _pickingDate = false;
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
    final dependencyLocked = flag.key == 'embed_links' && _sendPlain.banned;
    final isLocked = flag.locked || dependencyLocked;

    return InkWell(
      onTap: () {
        if (flag.locked) {
          showTelegramToast(context, 'You cannot change this permission.');
          return;
        }
        if (dependencyLocked) return;
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
      onTap: () => _selectDuration(value),
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
                onChanged: (v) => _selectDuration(v!),
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
  // AyuGram removes ManageTopics from group admin rights when !isForum
  // (NestedAdminRightLabels, edit_peer_permissions_box.cpp:146-153).
  bool isForum = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _EditAdminBox(
      accountId: accountId,
      chatId: chatId,
      member: member,
      isChannel: isChannel,
      promotedBy: promotedBy,
      isForum: isForum,
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
  final bool isForum;

  const _EditAdminBox({
    required this.accountId,
    required this.chatId,
    required this.member,
    required this.isChannel,
    this.promotedBy,
    this.isForum = false,
  });

  @override
  State<_EditAdminBox> createState() => _EditAdminBoxState();
}

class _EditAdminBoxState extends State<_EditAdminBox>
    with SingleTickerProviderStateMixin {
  bool _addAsAdmin = true;
  bool _saving = false;
  // EditAdminBox::canTransferOwnership / hasRank inputs (edit_participant_box.cpp).
  bool _amCreator = false; // editor is the chat creator (am_creator flag)
  bool _isBroadcast = false; // peer is a broadcast channel (is_broadcast flag)
  late final bool _isSelfTarget; // edit target is the current user (isSelf)
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

  // AyuGram AdminRightsForOwnershipTransfer (edit_peer_permissions_box.cpp:1465)
  // takes every admin right EXCEPT Anonymous, so the transfer button toggles on
  // when all of those are selected — a group owner does NOT have to enable
  // "Remain anonymous" first.
  bool get _allOwnerTransferRightsSelected {
    for (final f in _allFlags) {
      if (f.key == 'anonymous') continue;
      if (!f.enabled) return false;
    }
    return true;
  }

  // AyuGram EditAdminBox::canTransferOwnership (edit_participant_box.cpp:654):
  // false for inaccessible/bot/self targets; otherwise the editor must be the
  // chat creator (amCreator). This gates the EXISTENCE of the transfer button.
  bool get _canTransferOwnership {
    if (widget.member.userId.isEmpty || widget.member.isBot || _isSelfTarget) {
      return false;
    }
    return _amCreator;
  }

  // AyuGram hasRank = canSave() && (chat || channel->isMegagroup())
  // (edit_participant_box.cpp:477): the custom-title (rank) field is only shown
  // for groups/megagroups, never for broadcast channels.
  bool get _hasRank => !_isBroadcast;

  @override
  void initState() {
    super.initState();
    _isBroadcast = widget.isChannel;
    _isSelfTarget = context.read<AppState>().selfUserIdFor(widget.accountId) ==
        widget.member.userId;
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
        // ManageTopics only for forum groups (NestedAdminRightLabels removes it
        // when !options.isForum, edit_peer_permissions_box.cpp:146-153).
        if (widget.isForum) _AdminFlag(key: 'manage_topics', label: 'Manage topics'),
        _AdminFlag(key: 'pin_messages', label: 'Pin messages'),
      ];
      _section2 = [
        _AdminFlag(key: 'post_stories', label: 'Post stories'),
        _AdminFlag(key: 'edit_stories', label: 'Edit stories'),
        _AdminFlag(key: 'delete_stories', label: 'Delete stories'),
      ];
      _section3 = [
        _AdminFlag(key: 'manage_call', label: 'Manage voice chats'),
        // ManageRanks sits between Manage calls and Remain anonymous for groups
        // (edit_peer_permissions_box.cpp:142); lng_rights_group_manage_ranks.
        _AdminFlag(key: 'manage_ranks', label: 'Edit member tags'),
        _AdminFlag(key: 'anonymous', label: 'Remain anonymous'),
        _AdminFlag(key: 'add_admins', label: 'Add new admins'),
      ];
      _section4 = [];
    }

    _loadChatFlags();
    if (widget.member.role == 'admin') {
      _addAsAdmin = true;
      _loadExistingRights();
    }
  }

  // Loads am_creator / is_broadcast for the chat so the transfer-ownership
  // button and the custom-title field are gated exactly as AyuGram gates them
  // (canTransferOwnership / hasRank). Runs for every target, not just admins.
  Future<void> _loadChatFlags() async {
    try {
      final engine = context.read<EngineService>();
      final flags = await engine.getChatPermissionFlags(
        widget.accountId,
        widget.chatId,
      );
      if (!mounted) return;
      setState(() {
        _amCreator = flags['am_creator'] == true;
        _isBroadcast = flags['is_broadcast'] == true;
      });
    } catch (_) {}
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
          // hasRank false (broadcast channel) ⇒ no custom title, like AyuGram's
          // _finishSave passing std::nullopt for the rank.
          _hasRank ? _rankCtrl.text.trim() : '',
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

  // AyuGram ChannelOwnershipTransfer::start (channel_ownership_transfer.cpp:48)
  // first probes the server with an empty password and routes PASSWORD_MISSING /
  // *_TOO_FRESH through PrePasswordErrorBox (passcode_box.cpp:1466) BEFORE asking
  // for the real password. We do the pre-flight 2FA-state check here (the
  // PASSWORD_MISSING case) and only then show the password box.
  Future<void> _confirmTransferOwnership() async {
    final engine = context.read<EngineService>();
    final pwState = await engine.getCloudPasswordState(widget.accountId);
    if (!mounted) return;
    final hasPassword = pwState?['hasPassword'] == true;
    if (!hasPassword) {
      _showTransferSecurityCheck();
      return;
    }
    _showTransferPasswordDialog();
  }

  // PrePasswordErrorBox / TransferPasswordError NoPassword case
  // (passcode_box.cpp:65-99,1466): the editor has no 2FA password, so ownership
  // cannot be transferred until Two-Step Verification is enabled.
  void _showTransferSecurityCheck() {
    final palette = PaletteProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    final about = _isBroadcast
        ? 'You can transfer this channel to ${widget.member.label} only if you have:'
        : 'You can transfer this group to ${widget.member.label} only if you have:';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text(
          'Security check',
          style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(about, style: TextStyle(color: subTextColor, fontSize: 14)),
            const SizedBox(height: 12),
            Text(
              '• Enabled Two-Step Verification more than 7 days ago.',
              style: TextStyle(color: subTextColor, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              '• Logged in on this device more than 24 hours ago.',
              style: TextStyle(color: subTextColor, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text(
              'Enable it in Settings → Privacy and Security → Two-Step Verification, '
              'then come back later.',
              style: TextStyle(color: subTextColor, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK', style: TextStyle(color: palette.windowActiveTextFg)),
          ),
        ],
      ),
    );
  }

  void _showTransferPasswordDialog() {
    final palette = PaletteProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    final label = _isBroadcast ? 'channel' : 'group';
    final passwordCtrl = TextEditingController();
    bool obscure = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: bgColor,
          // lng_rights_transfer_password_title.
          title: Text(
            'Two-step verification',
            style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // lng_rights_transfer_about.
              Text(
                'This will transfer the full owner rights for this $label to '
                '${widget.member.label}. The new owner will be free to remove any '
                'of your admin privileges or even ban you.',
                style: TextStyle(color: subTextColor, fontSize: 14),
              ),
              const SizedBox(height: 16),
              // lng_rights_transfer_password_description.
              Text(
                'Please enter your password to complete the transfer.',
                style: TextStyle(color: subTextColor, fontSize: 14),
              ),
              const SizedBox(height: 8),
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
                    // lng_rights_transfer_done_group / _channel.
                    showTelegramToast(
                      context,
                      _isBroadcast
                          ? '${widget.member.label} is now the owner of the channel.'
                          : '${widget.member.label} is now the owner of the group.',
                    );
                    Navigator.of(context).pop(true);
                  }
                } catch (e) {
                  if (mounted) {
                    showTelegramToast(context, _transferErrorMessage(e.toString()));
                  }
                }
              },
              // lng_rights_transfer_sure.
              child: const Text('Change owner'),
            ),
          ],
        ),
      ),
    );
  }

  // Maps MessagesEditChatCreator errors to AyuGram's specific messages
  // (channel_ownership_transfer.cpp:119-141 + passcode_box.cpp:65-99) instead of
  // the previous generic "Transfer failed: $e" toast.
  String _transferErrorMessage(String error) {
    if (error.contains('PASSWORD_MISSING')) {
      return 'Please enable Two-Step Verification to transfer ownership.';
    } else if (error.contains('PASSWORD_TOO_FRESH')) {
      return 'You enabled Two-Step Verification too recently. Please come back later.';
    } else if (error.contains('SESSION_TOO_FRESH')) {
      return 'You logged in on this device too recently. Please come back later.';
    } else if (error.contains('PASSWORD_HASH_INVALID') || error.contains('SRP')) {
      return 'Incorrect password. Please try again.';
    } else if (error.contains('CHANNELS_ADMIN_PUBLIC_TOO_MUCH')) {
      return 'Sorry, the target user has too many public groups or channels already. '
          'Please ask them to make one of their existing groups or channels private first.';
    } else if (error.contains('CHANNELS_ADMIN_LOCATED_TOO_MUCH')) {
      return 'Sorry, the target user has too many location-based groups already.';
    } else if (error.contains('ADMINS_TOO_MUCH')) {
      return _isBroadcast
          ? "Sorry, you've reached the maximum number of admins for this channel."
          : "Sorry, you've reached the maximum number of admins for this group.";
    } else if (error.contains('CHANNEL_INVALID') ||
        error.contains('CHAT_CREATOR_REQUIRED') ||
        error.contains('PARTICIPANT_MISSING')) {
      return _isBroadcast
          ? 'Sorry, this channel is not accessible.'
          : 'Sorry, this group is not accessible.';
    }
    return 'Transfer failed: $error';
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
                        if (_hasRank) ...[
                          Divider(height: 1, color: dividerColor),
                          const SizedBox(height: 8),
                          _buildRankField(textColor, subTextColor),
                          const SizedBox(height: 8),
                        ],
                        if (_canTransferOwnership &&
                            _allOwnerTransferRightsSelected) ...[
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
  // Per-admin filter (FilterBox "admins" selector). null = all admins.
  List<MemberInfo> _adminList = [];
  Set<String>? _selectedAdminIds;

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
        admins: _selectedAdminIds?.toList(),
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
        if (_itemKeys.length > 150) {
          final keysToRemove = _itemKeys.keys.toList()..sort();
          for (final k in keysToRemove.take(_itemKeys.length - 100)) {
            _itemKeys.remove(k);
          }
        }
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

    final labelChanged = _currentDateLabel != newLabel;
    final needsShow = _dateBadgeOpacity != 1.0;
    if (labelChanged || needsShow) {
      setState(() {
        _currentDateLabel = newLabel;
        _dateBadgeOpacity = 1.0;
      });
    }
    _dateHideTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted && _dateBadgeOpacity != 0.0) {
        setState(() => _dateBadgeOpacity = 0.0);
      }
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

  Future<void> _showFilterDialog() async {
    // Lazily load the admin list once so the FilterBox can offer a per-admin
    // selector (history_admin_log_inner.cpp:522).
    if (_adminList.isEmpty) {
      try {
        final res = await context.read<EngineService>().getChatMembersByRole(
          widget.accountId,
          widget.chatId,
          role: 'admins',
          limit: 200,
        );
        _adminList = res.members;
      } catch (_) {}
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => _AdminLogFilterDialog(
        isChannel: widget.isChannel,
        initialChecks: _activeChecks,
        admins: _adminList,
        initialSelectedAdminIds: _selectedAdminIds,
        onApply: (filters, checks, selectedAdminIds) {
          _activeFilters = filters;
          _activeChecks = checks;
          _selectedAdminIds = selectedAdminIds;
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
                // Media preview surrogate for the real message bubble: a
                // thumbnail + media-type label + caption, so photo/video/file/
                // sticker entries no longer render blank
                // (history_admin_log_item.cpp:1027).
                if (_mediaType != 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _buildMessagePreview(
                      accentColor,
                      // Edits show the caption diff in the old/new blocks below,
                      // so the preview omits the caption to avoid duplication.
                      showCaption: event.action != 'edit_message',
                    ),
                  ),
                if (_mediaType == 0 && event.msgText.isNotEmpty && event.action != 'edit_message')
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

  int get _mediaType => (event.actionData['media_type'] as num?)?.toInt() ?? 0;
  String get _thumbB64 => event.actionData['thumb_b64'] as String? ?? '';

  static String _mediaLabel(int t) {
    switch (t) {
      case 1: return 'Photo';
      case 2: return 'Video';
      case 4: return 'Voice message';
      case 5: return 'Video message';
      case 6: return 'Sticker';
      case 7: return 'GIF';
      case 9: return 'File';
      case 10: return 'Audio';
      default: return 'Media';
    }
  }

  static IconData _mediaIcon(int t) {
    switch (t) {
      case 1: return Icons.photo_outlined;
      case 2: return Icons.videocam_outlined;
      case 4: return Icons.mic_none;
      case 5: return Icons.videocam_outlined;
      case 6: return Icons.emoji_emotions_outlined;
      case 7: return Icons.gif_box_outlined;
      case 9: return Icons.insert_drive_file_outlined;
      case 10: return Icons.audiotrack;
      default: return Icons.attachment;
    }
  }

  // Surrogate for AyuGram's real message bubble: a stripped-thumb image (no
  // network round-trip), a media-type label, and the caption.
  Widget _buildMessagePreview(Color accentColor, {bool showCaption = true}) {
    final caption = showCaption ? event.msgText : '';
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: accentColor, width: 2)),
        color: isDark ? const Color(0x20FFFFFF) : const Color(0x10000000),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _thumbB64.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.memory(
                    base64Decode(_thumbB64),
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) =>
                        Icon(_mediaIcon(_mediaType), size: 22, color: subTextColor),
                  ),
                )
              : Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(_mediaIcon(_mediaType), size: 20, color: accentColor),
                ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _mediaLabel(_mediaType),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accentColor),
                ),
                if (caption.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      caption,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: textColor),
                    ),
                  ),
              ],
            ),
          ),
        ],
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
        return 'changed the ${isChannel ? 'channel' : 'group'} title';
      case 'change_about':
        return 'changed the ${isChannel ? 'channel' : 'group'} description';
      case 'change_username':
        return 'changed the ${isChannel ? 'channel' : 'group'} link';
      case 'change_photo':
        return 'changed the ${isChannel ? 'channel' : 'group'} photo';
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
      case 'participant_edit_rank': {
        // set / changed / removed-rank family (history_admin_log_item.cpp:2167).
        final prev = event.actionData['prev_rank'] as String? ?? '';
        final next = event.actionData['new_rank'] as String? ?? '';
        final target = event.actionData['rank_user'] as String? ?? '';
        final who = target.isNotEmpty ? ' for $target' : '';
        if (next.isEmpty) {
          return 'removed custom title$who${prev.isNotEmpty ? ' "$prev"' : ''}';
        }
        if (prev.isEmpty) {
          return 'set custom title$who to "$next"';
        }
        return 'changed custom title$who to "$next"';
      }
      case 'change_pay_messages':
      case 'change_stars_price':
        return 'changed paid messages settings${event.detail.isNotEmpty ? " (${event.detail})" : ""}';
      case 'toggle_bot_membership':
        return '${event.detail.isNotEmpty ? event.detail : "changed"} bot membership';
      case 'change_peer_wallpaper':
        return 'changed the ${isChannel ? "channel" : "group"} wallpaper';
      case 'toggle_forum_topics':
        return '${event.detail.isNotEmpty ? event.detail : "toggled"} forum topics';
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
  final List<MemberInfo> admins;
  final Set<String>? initialSelectedAdminIds;
  final void Function(
    Map<String, bool>? filters,
    Map<String, bool> checks,
    Set<String>? selectedAdminIds,
  ) onApply;

  const _AdminLogFilterDialog({
    required this.isChannel,
    this.initialChecks,
    this.admins = const [],
    this.initialSelectedAdminIds,
    required this.onApply,
  });

  @override
  State<_AdminLogFilterDialog> createState() => _AdminLogFilterDialogState();
}

class _AdminLogFilterDialogState extends State<_AdminLogFilterDialog> {
  final Map<String, bool> _checks = {};
  // Per-admin selection. null entry / all-selected == "All admins".
  final Set<String> _selectedAdminIds = {};
  bool _adminsExpanded = false;

  static const _labelToFilterKeys = {
    'Admin rights': ['promote', 'demote'],
    'Edit rank': ['edit_rank'],
    'Restrictions': ['ban', 'unban', 'kick', 'unkick'],
    'New members': ['join', 'invite'],
    'Removed members': ['leave'],
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
  List<String> get _settingsSection => [
    'Info and settings',
    'Invite links',
    'Voice chats',
    'Subscription extensions',
    if (!widget.isChannel) 'Topics',
  ];
  List<String> get _messageSection => [
    'Deleted messages',
    'Edited messages',
    if (!widget.isChannel) 'Pinned messages',
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
    // Seed admin selection: a non-null previous selection restores those ids;
    // otherwise "All admins" (every admin selected).
    if (widget.initialSelectedAdminIds != null) {
      _selectedAdminIds.addAll(widget.initialSelectedAdminIds!);
    } else {
      _selectedAdminIds.addAll(widget.admins.map((a) => a.userId));
    }
  }

  bool get _allAdminsSelected =>
      widget.admins.isNotEmpty &&
      _selectedAdminIds.length == widget.admins.length;

  // Returns null when all admins are selected (== no admin filter).
  Set<String>? _buildAdminFilter() {
    if (widget.admins.isEmpty || _allAdminsSelected) return null;
    return Set<String>.from(_selectedAdminIds);
  }

  void _toggleAllAdmins() {
    setState(() {
      if (_allAdminsSelected) {
        _selectedAdminIds.clear();
      } else {
        _selectedAdminIds
          ..clear()
          ..addAll(widget.admins.map((a) => a.userId));
      }
    });
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
                      widget.onApply(
                        _buildFilters(),
                        Map<String, bool>.from(_checks),
                        _buildAdminFilter(),
                      );
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
                  if (widget.admins.isNotEmpty) ...[
                    Divider(height: 1, color: dividerColor),
                    _buildAdminsSection(headerColor, accentColor, textColor, isDark),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminsSection(
    Color headerColor,
    Color accentColor,
    Color textColor,
    bool isDark,
  ) {
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 4),
          child: Text(
            'Admins',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: headerColor),
          ),
        ),
        // "All admins" master row + expand toggle.
        InkWell(
          onTap: _toggleAllAdmins,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _allAdminsSelected,
                    tristate: true,
                    onChanged: (_) => _toggleAllAdmins(),
                    activeColor: accentColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('All admins', style: TextStyle(fontSize: 14, color: textColor)),
                ),
                GestureDetector(
                  onTap: () => setState(() => _adminsExpanded = !_adminsExpanded),
                  child: Icon(
                    _adminsExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 22,
                    color: subTextColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_adminsExpanded)
          for (final admin in widget.admins)
            InkWell(
              onTap: () => setState(() {
                if (_selectedAdminIds.contains(admin.userId)) {
                  _selectedAdminIds.remove(admin.userId);
                } else {
                  _selectedAdminIds.add(admin.userId);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: _selectedAdminIds.contains(admin.userId),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selectedAdminIds.add(admin.userId);
                          } else {
                            _selectedAdminIds.remove(admin.userId);
                          }
                        }),
                        activeColor: accentColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _AdminAvatar(member: admin, accentColor: accentColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        admin.label,
                        style: TextStyle(fontSize: 14, color: textColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
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

// Small avatar used in the admin-log filter's per-admin selector.
class _AdminAvatar extends StatelessWidget {
  final MemberInfo member;
  final Color accentColor;
  const _AdminAvatar({required this.member, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final hasAvatar = member.avatarB64.isNotEmpty;
    return CircleAvatar(
      radius: 14,
      backgroundColor: accentColor,
      backgroundImage: hasAvatar ? MemoryImage(base64Decode(member.avatarB64)) : null,
      child: hasAvatar
          ? null
          : Text(
              member.label.isNotEmpty ? member.label[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
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
  final bool adminIsBot;

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
    this.adminIsBot = false,
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
      adminIsBot: m['admin_is_bot'] as bool? ?? false,
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
  final bool isPublic;
  final String adminId;
  const _InviteLinksBox({required this.accountId, required this.chatId, required this.isChannel, this.isPublic = false, this.adminId = ''});

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
        isChannel: widget.isChannel,
        isPublic: widget.isPublic,
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
        isChannel: widget.isChannel,
        isPublic: widget.isPublic,
        existingLink: link,
      ),
    );
    if (result != null) _loadAll();
  }

  void _showLinkInfo(_InviteLinkData link) {
    String adminName = '';
    for (final a in _adminsWithInvites) {
      if ((a['admin_id'] as String? ?? '') == link.adminId) {
        adminName = (a['admin_name'] as String? ?? '').trim();
        break;
      }
    }
    showDialog(
      context: context,
      builder: (ctx) => _LinkInfoBox(
        accountId: widget.accountId,
        chatId: widget.chatId,
        link: link,
        adminName: adminName,
        // Edit/Revoke are suppressed for bot-created links (admin->isBot()).
        onRevoke: link.adminIsBot ? null : () { Navigator.pop(ctx); _revokeLink(link); },
        onEdit: link.adminIsBot ? null : () { Navigator.pop(ctx); _editLink(link); },
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
        // Edit/Revoke are hidden for bot-created links (edit_peer_invite_link.cpp:484).
        if (!link.revoked && !link.adminIsBot) ...[
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

class _LinkInfoBox extends StatefulWidget {
  final String accountId;
  final String chatId;
  final _InviteLinkData link;
  final String adminName;
  final VoidCallback? onRevoke;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _LinkInfoBox({
    required this.accountId,
    required this.chatId,
    required this.link,
    this.adminName = '',
    this.onRevoke,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<_LinkInfoBox> createState() => _LinkInfoBoxState();
}

class _LinkInfoBoxState extends State<_LinkInfoBox> {
  // Per-link joined members and pending join-requests (edit_peer_invite_link.cpp:592).
  List<Map<String, dynamic>> _joined = [];
  List<Map<String, dynamic>> _requests = [];
  bool _loadingJoined = true;
  bool _loadingRequests = false;
  final Set<String> _processing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final engine = context.read<EngineService>();
    try {
      final res = await engine.getInviteImporters(widget.accountId, widget.chatId, widget.link.link);
      if (mounted) {
        setState(() {
          _joined = (res['importers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _loadingJoined = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingJoined = false);
    }
    // The "Requests to join" block only exists for links that need approval.
    if (widget.link.needApproval) {
      if (mounted) setState(() => _loadingRequests = true);
      try {
        final res = await engine.getInviteImporters(widget.accountId, widget.chatId, widget.link.link,
            requested: true);
        if (mounted) {
          setState(() {
            _requests = (res['importers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
            _loadingRequests = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _loadingRequests = false);
      }
    }
  }

  Future<void> _process(String userId, bool approved) async {
    if (userId.isEmpty || _processing.contains(userId)) return;
    setState(() => _processing.add(userId));
    final engine = context.read<EngineService>();
    try {
      await engine.processJoinRequest(widget.accountId, widget.chatId, userId, approved);
      if (mounted) {
        setState(() {
          _requests.removeWhere((r) => r['user_id'] == userId);
          _processing.remove(userId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processing.remove(userId));
        showTelegramToast(context, 'Failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = PaletteProvider.of(context);
    final link = widget.link;
    final textColor = palette.windowFg;
    final subColor = palette.windowSubTextFg;
    final colorState = _linkColorState(link);
    final color = _linkColor(colorState, palette);

    return Dialog(
      backgroundColor: palette.boxBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 364, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
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
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      if (widget.adminName.isNotEmpty)
                        _infoRow('Created by', widget.adminName, textColor, subColor),
                      _infoRow('Joined', '${link.usage}', textColor, subColor),
                      if (link.usageLimit > 0)
                        _infoRow('Remaining', '${link.usageLimit - link.usage}', textColor, subColor),
                      if (link.expireDate > 0)
                        _infoRow('Expires', _formatExpiry(link.expireDate), textColor, subColor),
                      if (link.requested > 0)
                        _infoRow('Pending', '${link.requested}', textColor, subColor),
                      const SizedBox(height: 8),
                      if (!link.revoked) ...[
                        if (widget.onEdit != null)
                          TextButton.icon(onPressed: widget.onEdit, icon: const Icon(Icons.edit, size: 18), label: const Text('Edit Link')),
                        if (widget.onRevoke != null)
                          TextButton.icon(
                            onPressed: widget.onRevoke,
                            icon: Icon(Icons.link_off, size: 18, color: Theme.of(context).colorScheme.error),
                            label: Text('Revoke Link', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          ),
                      ],
                      if (link.revoked && widget.onDelete != null)
                        TextButton.icon(
                          onPressed: widget.onDelete,
                          icon: Icon(Icons.delete, size: 18, color: Theme.of(context).colorScheme.error),
                          label: Text('Delete Link', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ),
                      // Requests to join (per-link, approval-required links only).
                      if (link.needApproval) ...[
                        const SizedBox(height: 4),
                        _sectionLabel('Requests to Join', palette.windowBgActive),
                        if (_loadingRequests)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                          )
                        else if (_requests.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text('No pending requests', style: TextStyle(fontSize: 13, color: subColor)),
                          )
                        else
                          for (final r in _requests)
                            _importerRow(r, palette, textColor, subColor, isRequest: true),
                      ],
                      // Members who joined via this link.
                      const SizedBox(height: 4),
                      _sectionLabel('Joined via this link', palette.windowBgActive),
                      if (_loadingJoined)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                        )
                      else if (_joined.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text('No members joined yet', style: TextStyle(fontSize: 13, color: subColor)),
                        )
                      else
                        for (final m in _joined)
                          _importerRow(m, palette, textColor, subColor, isRequest: false),
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

  Widget _sectionLabel(String text, Color accent) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: accent)),
      );

  Widget _importerRow(Map<String, dynamic> m, TelegramPalette palette, Color textColor, Color subColor,
      {required bool isRequest}) {
    final userId = m['user_id'] as String? ?? '';
    final name = (m['display_name'] as String?)?.trim();
    final username = m['username'] as String? ?? '';
    final avatarB64 = m['avatar_b64'] as String? ?? '';
    final display = (name != null && name.isNotEmpty) ? name : (username.isNotEmpty ? '@$username' : userId);
    final processing = _processing.contains(userId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: palette.windowBgActive,
            backgroundImage: avatarB64.isNotEmpty ? MemoryImage(base64Decode(avatarB64)) : null,
            child: avatarB64.isEmpty
                ? Text(display.isNotEmpty ? display[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 12))
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(display,
                style: TextStyle(color: textColor, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (isRequest) ...[
            if (processing)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            else ...[
              TextButton(
                onPressed: () => _process(userId, true),
                style: TextButton.styleFrom(foregroundColor: palette.windowBgActive, padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('Add'),
              ),
              TextButton(
                onPressed: () => _process(userId, false),
                style: TextButton.styleFrom(foregroundColor: subColor, padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('Dismiss'),
              ),
            ],
          ],
        ],
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
  final bool isChannel;
  final bool isPublic;
  final _InviteLinkData? existingLink;
  const _CreateEditLinkForm({
    required this.accountId,
    required this.chatId,
    this.isChannel = false,
    this.isPublic = false,
    this.existingLink,
  });

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
              // Request Approval toggle (first per AyuGram order). Hidden for
              // public channels and subscription links: AyuGram sets
              // requestApproval = (isPublic || subscriptionLocked) ? nullptr
              // (edit_invite_link.cpp:112).
              if (!_subscriptionLocked && !widget.isPublic) ...[
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
              // Subscription toggle — channels only (fillSubscription is null for
              // groups, edit_peer_invite_link.cpp:1623) and only for private
              // channels (gated on !isPublic, edit_invite_link.cpp:136).
              if (widget.isChannel && !widget.isPublic) ...[
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
  bool isForum = false,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _MemberListScreen(
        accountId: accountId,
        chatId: chatId,
        isChannel: isChannel,
        initialTab: initialTab,
        isForum: isForum,
      ),
    ),
  );
}

class _MemberListScreen extends StatefulWidget {
  final String accountId;
  final String chatId;
  final bool isChannel;
  final _MemberTab initialTab;
  final bool isForum;

  const _MemberListScreen({
    required this.accountId,
    required this.chatId,
    required this.isChannel,
    required this.initialTab,
    this.isForum = false,
  });

  @override
  State<_MemberListScreen> createState() => _MemberListScreenState();
}

class _MemberListScreenState extends State<_MemberListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  // Roles chosen per peer: a broadcast channel has no restrict-without-kick
  // path, so no "Restricted" tab (edit_participants_box.cpp:1086).
  late final List<_MemberTab> _visibleTabs;
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';

  final Map<_MemberTab, List<MemberInfo>> _members = {};
  final Map<_MemberTab, bool> _loading = {};
  final Map<_MemberTab, bool> _hasMore = {};
  final Map<_MemberTab, int> _offsets = {};

  // Member-management capabilities for gating each Add button (canAddNewItem).
  bool _canAddAdmins = false;
  bool _canBanUsers = false;
  bool _canInviteUsers = false;

  static const _firstPageCount = 16;
  static const _pageSize = 200;

  @override
  void initState() {
    super.initState();
    _visibleTabs = [
      _MemberTab.members,
      _MemberTab.admins,
      if (!widget.isChannel) _MemberTab.restricted,
      _MemberTab.kicked,
      _MemberTab.requests,
    ];
    final initialIdx = _visibleTabs.indexOf(widget.initialTab);
    _tabCtrl = TabController(
      length: _visibleTabs.length,
      vsync: this,
      initialIndex: initialIdx < 0 ? 0 : initialIdx,
    );
    _tabCtrl.addListener(_onTabChanged);
    for (final tab in _MemberTab.values) {
      _members[tab] = [];
      _loading[tab] = false;
      _hasMore[tab] = true;
      _offsets[tab] = 0;
    }
    _loadCapabilities();
    _loadPage(_visibleTabs[_tabCtrl.index]);
  }

  Future<void> _loadCapabilities() async {
    try {
      final flags = await context.read<EngineService>().getChatPermissionFlags(
        widget.accountId,
        widget.chatId,
      );
      if (mounted) {
        setState(() {
          _canAddAdmins = flags['can_add_admins'] == true;
          _canBanUsers = flags['can_ban_users'] == true;
          _canInviteUsers = flags['can_invite_users'] == true;
        });
      }
    } catch (_) {}
  }

  bool _canAddForTab(_MemberTab tab) {
    switch (tab) {
      case _MemberTab.members:
        // "Add Members" — only for groups (you don't add subscribers to a
        // broadcast channel from here) and only with invite rights.
        return !widget.isChannel && _canInviteUsers;
      case _MemberTab.admins:
        return _canAddAdmins;
      case _MemberTab.restricted:
      case _MemberTab.kicked:
        return _canBanUsers;
      default:
        return false;
    }
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
    final tab = _visibleTabs[_tabCtrl.index];
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
      _loadPage(_visibleTabs[_tabCtrl.index]);
    });
  }

  String _tabLabel(_MemberTab tab) {
    switch (tab) {
      case _MemberTab.members:
        return widget.isChannel ? 'Subscribers' : 'Members';
      case _MemberTab.admins:
        return 'Admins';
      case _MemberTab.restricted:
        return 'Restricted';
      case _MemberTab.kicked:
        return 'Removed';
      case _MemberTab.requests:
        return 'Requests';
    }
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
                tabs: _visibleTabs.map((t) => Tab(text: _tabLabel(t))).toList(),
              ),
              Divider(height: 1, color: dividerColor),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: _visibleTabs.map((tab) {
          return _MemberTabBody(
            members: _members[tab]!,
            loading: _loading[tab]!,
            hasMore: _hasMore[tab]!,
            tab: tab,
            isChannel: widget.isChannel,
            canAdd: _canAddForTab(tab),
            accountId: widget.accountId,
            chatId: widget.chatId,
            isForum: widget.isForum,
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
  final bool canAdd;
  final String accountId;
  final String chatId;
  final VoidCallback onLoadMore;
  final VoidCallback onRefresh;
  final Color textColor;
  final Color subColor;
  final Color accentColor;
  final bool isDark;
  final bool isForum;

  const _MemberTabBody({
    required this.members,
    required this.loading,
    required this.hasMore,
    required this.tab,
    required this.isChannel,
    this.canAdd = false,
    required this.accountId,
    required this.chatId,
    required this.onLoadMore,
    required this.onRefresh,
    required this.textColor,
    required this.subColor,
    required this.accentColor,
    required this.isDark,
    this.isForum = false,
  });

  // The Add button only appears on admins/restricted/kicked tabs AND only when
  // the editor has the matching right (canAddNewItem → canAddAdmins/canBanMembers).
  bool get _showAddButton =>
      canAdd &&
      (tab == _MemberTab.members ||
          tab == _MemberTab.kicked ||
          tab == _MemberTab.restricted ||
          tab == _MemberTab.admins);

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
                  : tab == _MemberTab.requests
                      ? 'There are no pending join requests.'
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
            isForum: isForum,
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

  void _showAddMemberDialog(BuildContext ctx) async {
    final engine = ctx.read<EngineService>();
    final title = switch (tab) {
      _MemberTab.kicked => 'Ban User',
      _MemberTab.admins => 'Add Admin',
      _MemberTab.restricted => 'Add Exception',
      _ => 'Add Members',
    };
    // Add Member is a multi-select contact picker (ContactsBoxController);
    // Add Admin/Exception/Banned is a single-select searchable participant/
    // contact picker (AddSpecialBoxController). Both replace the old free-text
    // username/ID box (add_participants_box.cpp:768 / 1234).
    final isMembersTab = tab == _MemberTab.members;
    final selected = await showDialog<List<String>>(
      context: ctx,
      builder: (_) => _MemberPickerDialog(
        accountId: accountId,
        chatId: chatId,
        title: title,
        multiSelect: isMembersTab,
        includeMembers: !isMembersTab,
        isDark: isDark,
        accentColor: accentColor,
      ),
    );
    if (selected == null || selected.isEmpty) return;
    try {
      if (isMembersTab) {
        await engine.addMembers(accountId, chatId, selected);
      } else {
        for (final userId in selected) {
          if (tab == _MemberTab.kicked) {
            await engine.banMember(accountId, chatId, userId);
          } else if (tab == _MemberTab.admins) {
            await engine.promoteAdmin(accountId, chatId, userId);
          } else {
            await engine.restrictMember(accountId, chatId, userId);
          }
        }
      }
      onRefresh();
      if (ctx.mounted) showTelegramToast(ctx, 'Done');
    } catch (e) {
      if (ctx.mounted) showTelegramToast(ctx, 'Failed: $e');
    }
  }
}

// Searchable participant/contact picker that replaces the old free-text
// username/ID box. multiSelect=true → ContactsBoxController (Add Members);
// multiSelect=false → AddSpecialBoxController (Add Admin/Exception/Banned).
class _PickerEntry {
  final String id;
  final String name;
  final String username;
  final String avatarB64;
  _PickerEntry(this.id, this.name, this.username, this.avatarB64);
}

class _MemberPickerDialog extends StatefulWidget {
  final String accountId;
  final String chatId;
  final String title;
  final bool multiSelect;
  final bool includeMembers;
  final bool isDark;
  final Color accentColor;
  const _MemberPickerDialog({
    required this.accountId,
    required this.chatId,
    required this.title,
    required this.multiSelect,
    required this.includeMembers,
    required this.isDark,
    required this.accentColor,
  });

  @override
  State<_MemberPickerDialog> createState() => _MemberPickerDialogState();
}

class _MemberPickerDialogState extends State<_MemberPickerDialog> {
  final _searchCtrl = TextEditingController();
  List<_PickerEntry> _all = [];
  List<_PickerEntry> _filtered = [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _resolving = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final engine = context.read<EngineService>();
    final byId = <String, _PickerEntry>{};
    try {
      final contacts = await engine.getContacts(widget.accountId);
      for (final c in contacts) {
        byId[c.userId] = _PickerEntry(c.userId, c.displayName, c.username, c.avatarB64);
      }
    } catch (_) {}
    // For special-member adds, also seed with the chat's existing participants
    // (AddSpecialBoxController searches participants → members → contacts → global).
    if (widget.includeMembers) {
      try {
        final res = await engine.getChatMembersByRole(widget.accountId, widget.chatId,
            role: 'members', limit: 100);
        for (final m in res.members) {
          byId[m.userId] = _PickerEntry(m.userId, m.displayName, m.username, m.avatarB64);
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _all = byId.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _filtered = _all;
      _loading = false;
    });
  }

  void _onSearch(String q) {
    final ql = q.trim().toLowerCase();
    setState(() {
      _query = q.trim();
      _filtered = ql.isEmpty
          ? _all
          : _all
              .where((e) =>
                  e.name.toLowerCase().contains(ql) || e.username.toLowerCase().contains(ql))
              .toList();
    });
  }

  // Resolves a username not in the local list and adds it (global search step).
  Future<void> _resolveGlobal() async {
    final q = _query.startsWith('@') ? _query.substring(1) : _query;
    if (q.isEmpty || _resolving) return;
    setState(() => _resolving = true);
    final engine = context.read<EngineService>();
    try {
      final id = await engine.resolveUsername(widget.accountId, q);
      if (id != null && id.isNotEmpty) {
        String name = q;
        try {
          final p = await engine.getUserProfile(widget.accountId, id);
          if (p != null && p.displayName.isNotEmpty) name = p.displayName;
        } catch (_) {}
        final entry = _PickerEntry(id, name, q, '');
        if (mounted) {
          setState(() {
            if (!_all.any((e) => e.id == id)) _all = [entry, ..._all];
            _filtered = [entry];
            _resolving = false;
          });
        }
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _resolving = false);
      showTelegramToast(context, 'User not found');
    }
  }

  void _toggle(String id) {
    if (widget.multiSelect) {
      setState(() {
        if (_selected.contains(id)) {
          _selected.remove(id);
        } else {
          _selected.add(id);
        }
      });
    } else {
      Navigator.pop(context, [id]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    return AlertDialog(
      backgroundColor: bg,
      title: Text(widget.title, style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 340,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: TextStyle(color: textColor, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search',
                hintStyle: TextStyle(color: subColor),
                prefixIcon: Icon(Icons.search, color: subColor),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: _onSearch,
              onSubmitted: (_) {
                if (_filtered.isEmpty) _resolveGlobal();
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('No matches', style: TextStyle(color: subColor)),
                              if (_query.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _resolving
                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                    : TextButton(
                                        onPressed: _resolveGlobal,
                                        child: Text('Search globally for "$_query"',
                                            style: TextStyle(color: widget.accentColor)),
                                      ),
                              ],
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filtered.length,
                          itemBuilder: (ctx, i) {
                            final e = _filtered[i];
                            final sel = _selected.contains(e.id);
                            return ListTile(
                              dense: true,
                              onTap: () => _toggle(e.id),
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: widget.accentColor,
                                backgroundImage: e.avatarB64.isNotEmpty ? MemoryImage(base64Decode(e.avatarB64)) : null,
                                child: e.avatarB64.isEmpty
                                    ? Text(e.name.isNotEmpty ? e.name[0].toUpperCase() : '?',
                                        style: const TextStyle(color: Colors.white, fontSize: 14))
                                    : null,
                              ),
                              title: Text(
                                e.name.isNotEmpty ? e.name : (e.username.isNotEmpty ? '@${e.username}' : e.id),
                                style: TextStyle(color: textColor, fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: e.username.isNotEmpty
                                  ? Text('@${e.username}', style: TextStyle(color: subColor, fontSize: 12))
                                  : null,
                              trailing: widget.multiSelect
                                  ? Icon(sel ? Icons.check_circle : Icons.radio_button_unchecked,
                                      color: sel ? widget.accentColor : subColor)
                                  : null,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: subColor))),
        if (widget.multiSelect)
          TextButton(
            onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, _selected.toList()),
            child: Text('Add${_selected.isNotEmpty ? ' (${_selected.length})' : ''}',
                style: TextStyle(color: widget.accentColor, fontWeight: FontWeight.w600)),
          ),
      ],
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
  final bool isForum;

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
    this.isForum = false,
  });

  // Request rows show "requested to join …" with the request timestamp
  // (member.promotedDate carries the join-request date). Mirrors AyuGram
  // PrepareRequestedRowStatus (edit_peer_invite_link.cpp:1736).
  String _requestedStatus() {
    final ts = member.promotedDate;
    if (ts <= 0) return 'wants to join';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final dateOnly = DateTime(dt.year, dt.month, dt.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(dateOnly).inDays;
    if (diff == 0) return 'requested to join today at $time';
    if (diff == 1) return 'requested to join yesterday at $time';
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return 'requested to join ${months[dt.month - 1]} ${dt.day} at $time';
  }

  String _statusText() {
    if (tab == _MemberTab.requests) return _requestedStatus();
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

    // Per-row gating mirrors AyuGram: can't act on the creator, on yourself, or
    // on an admin you didn't promote (edit_participants_box.cpp:1962).
    final isAdminTarget = member.role == 'admin' || member.role == 'creator';

    if (tab == _MemberTab.admins || tab == _MemberTab.members) {
      // "Edit admin rights" for an existing admin, "Promote" for a non-admin.
      if (member.canEditAdmin && !member.isCreator) {
        items.add(PopupMenuItem(
          value: 'promote',
          child: Text(isAdminTarget ? 'Edit Admin Rights' : 'Promote to Admin'),
        ));
      }
      // Restrict-without-kick only exists for groups, never a broadcast channel.
      if (!isChannel && member.canRestrict && !member.isCreator && !member.isSelf) {
        items.add(const PopupMenuItem(value: 'restrict', child: Text('Restrict User')));
      }
      if (member.canRestrict && !member.isCreator && !member.isSelf) {
        items.add(PopupMenuItem(
          value: 'remove',
          // Broadcast: lng_profile_kick ("Remove"); group: "Remove from Group".
          child: Text(isChannel ? 'Remove' : 'Remove from Group', style: TextStyle(color: Colors.red.shade400)),
        ));
      }
    }
    if (tab == _MemberTab.restricted && member.canRestrict) {
      items.add(const PopupMenuItem(value: 'restrict', child: Text('Edit Restrictions')));
      items.add(const PopupMenuItem(value: 'unban', child: Text('Remove Restrictions')));
    }
    if (tab == _MemberTab.kicked && member.canRestrict) {
      // AyuGram offers "Add to group" (unkick + re-add) AND "Delete" (remove from
      // the removed list) — not just Unban (edit_participants_box.cpp:1946).
      items.add(const PopupMenuItem(value: 'add_to_group', child: Text('Add to Group')));
      items.add(const PopupMenuItem(value: 'delete', child: Text('Delete')));
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
            isForum: isForum,
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
        case 'add_to_group':
          _doAddToGroup(context, engine);
          break;
        case 'delete':
          // Remove from the removed list (unban, no re-add).
          _doUnban(context, engine);
          break;
      }
    });
  }

  void _doAddToGroup(BuildContext context, EngineService engine) async {
    try {
      await engine.unbanChatMember(accountId, chatId, member.userId);
      await engine.addMembers(accountId, chatId, [member.userId]);
      onRefresh();
      if (context.mounted) showTelegramToast(context, 'Added to group');
    } catch (e) {
      if (context.mounted) showTelegramToast(context, 'Failed: $e');
    }
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

  // Approves or dismisses a pending join request. Mirrors AyuGram
  // RequestsBoxController::processRequest (edit_peer_requests_box.cpp:419):
  // approve/dismiss fire immediately (no confirm), the row is removed, and an
  // approval shows the "{user} has been added to the …" toast.
  void _processRequest(BuildContext context, EngineService engine, bool approved) async {
    try {
      await engine.processJoinRequest(accountId, chatId, member.userId, approved);
      if (context.mounted && approved) {
        showTelegramToast(
          context,
          '${member.label} has been added to the ${isChannel ? 'channel' : 'group'}.',
        );
      }
      onRefresh();
    } catch (e) {
      if (context.mounted) showTelegramToast(context, 'Failed: $e');
    }
  }

  // Accept (filled accent) + Dismiss (light) buttons for a join-request row.
  // Labels/sizing mirror requestsAcceptButton/requestsRejectButton + the
  // lng_group_requests_add[_channel]/dismiss strings (boxes.style:1006).
  Widget _buildRequestButtons(BuildContext context) {
    final engine = context.read<EngineService>();
    final lightBg = isDark
        ? accentColor.withValues(alpha: 0.18)
        : accentColor.withValues(alpha: 0.10);
    Widget button(String label, bool filled, VoidCallback onTap) {
      return Material(
        color: filled ? accentColor : lightBg,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 30,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: filled ? Colors.white : accentColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        Flexible(
          child: button(
            isChannel ? 'Add to Channel' : 'Add to Group',
            true,
            () => _processRequest(context, engine, true),
          ),
        ),
        const SizedBox(width: 9),
        button('Dismiss', false, () => _processRequest(context, engine, false)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRequest = tab == _MemberTab.requests;
    final mainRow = Row(
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
    );

    return InkWell(
      onSecondaryTapDown: (d) => _showContextMenu(context, d.globalPosition),
      onLongPress: () {
        final box = context.findRenderObject() as RenderBox;
        final pos = box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2));
        _showContextMenu(context, pos);
      },
      child: isRequest
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  mainRow,
                  const SizedBox(height: 8),
                  // Buttons left-aligned under the name (avatar 42 + 12 gap),
                  // matching AyuGram requestAcceptPosition x≈71 (boxes.style:1016).
                  Padding(
                    padding: const EdgeInsets.only(left: 54),
                    child: _buildRequestButtons(context),
                  ),
                ],
              ),
            )
          : SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: mainRow,
              ),
            ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// Statistics — full section page (AyuGram Info::ChannelStatistics / Megagroup)
// Renders overview counters with growth %, real line charts parsed from the
// Telegram StatsGraph JSON, and the recent-posts interaction list.
// ════════════════════════════════════════════════════════════════════════

class _StatisticsScreen extends StatefulWidget {
  final String accountId;
  final String chatId;
  final String title;
  final bool isBroadcast;

  const _StatisticsScreen({
    required this.accountId,
    required this.chatId,
    required this.title,
    required this.isBroadcast,
  });

  @override
  State<_StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<_StatisticsScreen> {
  Map<String, dynamic>? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final engine = context.read<EngineService>();
    try {
      final data = widget.isBroadcast
          ? await engine.getBroadcastStats(widget.accountId, widget.chatId)
          : await engine.getMegagroupStats(widget.accountId, widget.chatId);
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  static String _humanize(String key) {
    final parts = key.split('_');
    return parts.map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }

  // Megagroup member breakdown section (AddMembersList) — Top Senders /
  // Administrators / Inviters (info_statistics_inner_widget.cpp:743). Rows open
  // the member's profile.
  List<Widget> _buildTopList(
    String title,
    List list,
    Color cardColor,
    Color textColor,
    Color subTextColor,
    Color accentColor,
    String Function(Map) subtitle,
  ) {
    return [
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Text(title, style: TextStyle(color: subTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
      ...list.whereType<Map>().map((e) {
        final name = (e['name'] as String?)?.trim();
        final userId = e['user_id'] as String? ?? '';
        final display = (name != null && name.isNotEmpty) ? name : userId;
        return InkWell(
          onTap: userId.isEmpty
              ? null
              : () {
                  if (InfoPanel.pushUserProfileRequest != null) {
                    InfoPanel.pushUserProfileRequest!(
                        MemberInfo(userId: userId, displayName: display));
                  }
                },
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: accentColor,
                  child: Text(display.isNotEmpty ? display[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(display,
                          style: TextStyle(color: textColor, fontSize: 14),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(subtitle(e), style: TextStyle(color: subTextColor, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    ];
  }

  static String _fmtNum(num v) {
    if (v == v.roundToDouble()) {
      final s = v.round().toString();
      return s.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
    }
    return v.toStringAsFixed(2);
  }

  static String _fmtDate(int epochSec) {
    if (epochSec <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0E1621) : const Color(0xFFF0F0F0);
    final cardColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    final accentColor = PaletteProvider.of(context).windowBgActive;

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Failed to load statistics:\n$_error',
              style: TextStyle(color: subTextColor, fontSize: 14), textAlign: TextAlign.center),
        ),
      );
    } else {
      final data = _data ?? {};
      final periodMin = data['period_min'] as int? ?? 0;
      final periodMax = data['period_max'] as int? ?? 0;

      // Overview counter cards (value is a {current, previous, growth} map, or a plain number).
      final overview = <Widget>[];
      for (final entry in data.entries) {
        final key = entry.key;
        if (key == 'charts' || key == 'recent_posts' || key == 'period_min' || key == 'period_max') {
          continue;
        }
        final val = entry.value;
        num? current;
        double growth = 0;
        if (val is Map) {
          final c = val['current'];
          if (c is num) current = c;
          final g = val['growth'];
          if (g is num) growth = g.toDouble();
        } else if (val is num) {
          current = val;
        }
        if (current == null) continue;
        final isPct = key == 'enabled_notifications';
        overview.add(_StatCard(
          label: _humanize(key),
          value: isPct ? '${current.toStringAsFixed(2)}%' : _fmtNum(current),
          growth: growth,
          cardColor: cardColor,
          textColor: textColor,
          subTextColor: subTextColor,
        ));
      }

      final charts = (data['charts'] as List?) ?? const [];
      final chartWidgets = <Widget>[];
      for (final ch in charts) {
        if (ch is! Map) continue;
        // Render every graph (inline OR async); _StatChartWidget loads async
        // graphs on demand via their async_token instead of skipping them.
        chartWidgets.add(_StatChartWidget(
          accountId: widget.accountId,
          chart: ch,
          cardColor: cardColor,
          textColor: textColor,
          subTextColor: subTextColor,
        ));
      }

      final recentPosts = (data['recent_posts'] as List?) ?? const [];
      // Megagroup-only member breakdowns (Top Senders / Admins / Inviters).
      final topPosters = (data['top_posters'] as List?) ?? const [];
      final topAdmins = (data['top_admins'] as List?) ?? const [];
      final topInviters = (data['top_inviters'] as List?) ?? const [];

      body = ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          if (periodMin > 0 && periodMax > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('${_fmtDate(periodMin)} – ${_fmtDate(periodMax)}',
                  style: TextStyle(color: subTextColor, fontSize: 13)),
            ),
          if (overview.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(spacing: 8, runSpacing: 8, children: overview),
            ),
          if (chartWidgets.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text('Graphs',
                  style: TextStyle(color: subTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            ...chartWidgets,
          ],
          if (recentPosts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text('Recent posts',
                  style: TextStyle(color: subTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            ...recentPosts.whereType<Map>().map((p) => _RecentPostRow(
                  post: p,
                  accountId: widget.accountId,
                  chatId: widget.chatId,
                  cardColor: cardColor,
                  textColor: textColor,
                  subTextColor: subTextColor,
                  accentColor: accentColor,
                )),
          ],
          if (topPosters.isNotEmpty)
            ..._buildTopList('Top Members', topPosters, cardColor, textColor, subTextColor, accentColor,
                (e) {
              final msgs = (e['messages'] as num?)?.toInt() ?? 0;
              return '$msgs ${msgs == 1 ? 'message' : 'messages'}';
            }),
          if (topAdmins.isNotEmpty)
            ..._buildTopList('Top Admins', topAdmins, cardColor, textColor, subTextColor, accentColor,
                (e) {
              final parts = <String>[];
              final del = (e['deleted'] as num?)?.toInt() ?? 0;
              final ban = (e['banned'] as num?)?.toInt() ?? 0;
              final kick = (e['kicked'] as num?)?.toInt() ?? 0;
              if (del > 0) parts.add('$del deletions');
              if (ban > 0) parts.add('$ban bans');
              if (kick > 0) parts.add('$kick kicks');
              return parts.isEmpty ? 'admin' : parts.join(' · ');
            }),
          if (topInviters.isNotEmpty)
            ..._buildTopList('Top Inviters', topInviters, cardColor, textColor, subTextColor, accentColor,
                (e) {
              final inv = (e['invitations'] as num?)?.toInt() ?? 0;
              return '$inv ${inv == 1 ? 'invitation' : 'invitations'}';
            }),
          if (overview.isEmpty && chartWidgets.isEmpty && recentPosts.isEmpty &&
              topPosters.isEmpty && topAdmins.isEmpty && topInviters.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text('No statistics available yet.',
                    style: TextStyle(color: subTextColor, fontSize: 14)),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        foregroundColor: textColor,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Statistics', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            Text(widget.title, style: TextStyle(fontSize: 12, color: subTextColor)),
          ],
        ),
      ),
      body: body,
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final double growth;
  final Color cardColor;
  final Color textColor;
  final Color subTextColor;

  const _StatCard({
    required this.label,
    required this.value,
    required this.growth,
    required this.cardColor,
    required this.textColor,
    required this.subTextColor,
  });

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.of(context).size.width - 24 - 8) / 2;
    final growthColor = growth > 0
        ? const Color(0xFF4FAD2D)
        : (growth < 0 ? const Color(0xFFE53935) : subTextColor);
    return Container(
      width: width.clamp(120.0, 400.0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(value,
                    style: TextStyle(color: textColor, fontSize: 19, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
              ),
              if (growth != 0) ...[
                const SizedBox(width: 6),
                Text('${growth > 0 ? '+' : ''}${growth.toStringAsFixed(1)}%',
                    style: TextStyle(color: growthColor, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: subTextColor, fontSize: 12)),
        ],
      ),
    );
  }
}

class _RecentPostRow extends StatelessWidget {
  final Map post;
  final String accountId;
  final String chatId;
  final Color cardColor;
  final Color textColor;
  final Color subTextColor;
  final Color accentColor;

  const _RecentPostRow({
    required this.post,
    required this.accountId,
    required this.chatId,
    required this.cardColor,
    required this.textColor,
    required this.subTextColor,
    required this.accentColor,
  });

  static String _mediaLabel(int t) {
    switch (t) {
      case 1: return 'Photo';
      case 2: return 'Video';
      case 4: return 'Voice message';
      case 5: return 'Video message';
      case 6: return 'Sticker';
      case 7: return 'GIF';
      case 9: return 'File';
      case 10: return 'Audio';
      default: return 'Post';
    }
  }

  void _openMessageStats(BuildContext context, int msgId) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _MessageStatsScreen(accountId: accountId, chatId: chatId, msgId: msgId),
    ));
  }

  void _showMenu(BuildContext context, Offset pos, int msgId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      color: isDark ? const Color(0xFF1E2C3A) : Colors.white,
      items: const [
        PopupMenuItem(value: 'stats', child: Text('Message Statistics')),
        PopupMenuItem(value: 'show', child: Text('Show in Chat')),
      ],
    ).then((v) {
      if (v == 'stats' && msgId > 0) {
        _openMessageStats(context, msgId);
      } else if (v == 'show') {
        context.read<ChatState>().openChatById(chatId);
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final views = post['views'] as int? ?? 0;
    final forwards = post['forwards'] as int? ?? 0;
    final reactions = post['reactions'] as int? ?? 0;
    final msgId = post['msg_id'] as int? ?? 0;
    final text = (post['text'] as String?)?.trim() ?? '';
    final mediaType = post['media_type'] as int? ?? 0;
    final thumbB64 = post['thumb_b64'] as String? ?? '';
    final date = post['date'] as int? ?? 0;
    final preview = text.isNotEmpty ? text : _mediaLabel(mediaType);

    return GestureDetector(
      onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition, msgId),
      onLongPressStart: (d) => _showMenu(context, d.globalPosition, msgId),
      child: InkWell(
        onTap: msgId > 0 ? () => _openMessageStats(context, msgId) : null,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              // Message preview (thumbnail or media icon).
              if (thumbB64.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(base64Decode(thumbB64),
                      width: 40, height: 40, fit: BoxFit.cover, gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => _mediaIconBox(mediaType)),
                )
              else if (mediaType != 0)
                _mediaIconBox(mediaType),
              if (thumbB64.isNotEmpty || mediaType != 0) const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(preview,
                        style: TextStyle(color: textColor, fontSize: 14),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('${_StatisticsScreenState._fmtNum(views)} views',
                            style: TextStyle(color: subTextColor, fontSize: 12)),
                        const SizedBox(width: 10),
                        Icon(Icons.share_outlined, size: 13, color: subTextColor),
                        const SizedBox(width: 2),
                        Text(_StatisticsScreenState._fmtNum(forwards),
                            style: TextStyle(color: subTextColor, fontSize: 12)),
                        const SizedBox(width: 10),
                        Icon(Icons.favorite_border, size: 13, color: subTextColor),
                        const SizedBox(width: 2),
                        Text(_StatisticsScreenState._fmtNum(reactions),
                            style: TextStyle(color: subTextColor, fontSize: 12)),
                        if (date > 0) ...[
                          const Spacer(),
                          Text(_StatisticsScreenState._fmtDate(date),
                              style: TextStyle(color: subTextColor, fontSize: 11)),
                        ],
                      ],
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

  Widget _mediaIconBox(int mediaType) {
    IconData icon;
    switch (mediaType) {
      case 1: icon = Icons.photo_outlined; break;
      case 2:
      case 5: icon = Icons.videocam_outlined; break;
      case 6: icon = Icons.emoji_emotions_outlined; break;
      case 7: icon = Icons.gif_box_outlined; break;
      case 9: icon = Icons.insert_drive_file_outlined; break;
      case 4: icon = Icons.mic_none; break;
      case 10: icon = Icons.audiotrack; break;
      default: icon = Icons.article_outlined;
    }
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Icon(icon, size: 20, color: accentColor),
    );
  }
}

// How a statistics graph is drawn — mirrors AyuGram's ChartViewType
// (Linear/DoubleLinear → line, StackLinear → stacked area, Bar/StackBar → bars).
enum _ChartKind { line, bar, stackedBar, stackedArea }

/// A parsed Telegram statistics graph (columns of values, named/colored series).
class _StatChart {
  final String title;
  final List<List<double>> series; // each entry: a y-series of values
  final List<String> names;
  final List<Color> colors;
  final _ChartKind kind;

  _StatChart(this.title, this.series, this.names, this.colors, this.kind);

  static Color _hex(String? s) {
    if (s == null || s.isEmpty) return const Color(0xFF50A2E9);
    var h = s.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? const Color(0xFF50A2E9) : Color(v);
  }

  static _ChartKind _kindFor(String type, Map types) {
    switch (type) {
      case 'Bar':
        return _ChartKind.bar;
      case 'StackBar':
        return _ChartKind.stackedBar;
      case 'StackLinear':
        return _ChartKind.stackedArea;
      case 'Linear':
      case 'DoubleLinear':
        return _ChartKind.line;
      default:
        // Fall back to the per-column hint when the chart type is unknown.
        if (types.values.contains('bar')) return _ChartKind.stackedBar;
        if (types.values.contains('area')) return _ChartKind.stackedArea;
        return _ChartKind.line;
    }
  }

  static _StatChart? parse(String title, String jsonStr, {String type = 'Linear'}) {
    try {
      final obj = json.decode(jsonStr);
      if (obj is! Map) return null;
      final columns = obj['columns'];
      if (columns is! List) return null;
      final types = (obj['types'] as Map?) ?? const {};
      final names = (obj['names'] as Map?) ?? const {};
      final colors = (obj['colors'] as Map?) ?? const {};
      final series = <List<double>>[];
      final seriesNames = <String>[];
      final seriesColors = <Color>[];
      for (final col in columns) {
        if (col is! List || col.isEmpty) continue;
        final id = col.first.toString();
        if (id == 'x' || types[id] == 'x') continue; // skip the x axis
        final ys = <double>[];
        for (var i = 1; i < col.length; i++) {
          final v = col[i];
          ys.add(v is num ? v.toDouble() : 0);
        }
        if (ys.isEmpty) continue;
        series.add(ys);
        seriesNames.add((names[id] as String?) ?? id);
        seriesColors.add(_hex(colors[id] as String?));
      }
      if (series.isEmpty) return null;
      return _StatChart(title, series, seriesNames, seriesColors, _kindFor(type, types));
    } catch (_) {
      return null;
    }
  }

  Widget build(Color cardColor, Color textColor, Color subTextColor) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            width: double.infinity,
            child: CustomPaint(painter: _StatGraphPainter(series, colors, kind)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: List.generate(names.length, (i) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 10, height: 10,
                    decoration: BoxDecoration(color: colors[i], shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(names[i], style: TextStyle(color: subTextColor, fontSize: 12)),
              ],
            )),
          ),
        ],
      ),
    );
  }
}

// Loads + renders a single statistics graph. Inline-data graphs render
// immediately; async graphs (StatsGraphAsync) are fetched on demand via
// loadStatsGraph(async_token) — AyuGram's requestZoom(token, 0)
// (info_statistics_inner_widget.cpp:154). Previously async graphs rendered blank.
class _StatChartWidget extends StatefulWidget {
  final String accountId;
  final Map chart;
  final Color cardColor;
  final Color textColor;
  final Color subTextColor;
  const _StatChartWidget({
    required this.accountId,
    required this.chart,
    required this.cardColor,
    required this.textColor,
    required this.subTextColor,
  });

  @override
  State<_StatChartWidget> createState() => _StatChartWidgetState();
}

class _StatChartWidgetState extends State<_StatChartWidget> {
  _StatChart? _parsed;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final title = widget.chart['title'] as String? ?? '';
    final type = widget.chart['type'] as String? ?? 'Linear';
    var dataStr = widget.chart['data'];
    if (dataStr is! String || dataStr.isEmpty) {
      final token = widget.chart['async_token'] as String?;
      if (token != null && token.isNotEmpty) {
        try {
          final loaded = await context.read<EngineService>().loadStatsGraph(widget.accountId, token);
          dataStr = loaded['data'];
        } catch (_) {}
      }
    }
    _StatChart? parsed;
    if (dataStr is String && dataStr.isNotEmpty) {
      parsed = _StatChart.parse(title, dataStr, type: type);
    }
    if (mounted) {
      setState(() {
        _parsed = parsed;
        _loading = false;
        _failed = parsed == null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        height: 120,
        decoration: BoxDecoration(color: widget.cardColor, borderRadius: BorderRadius.circular(10)),
        child: const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (_failed || _parsed == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _parsed!.build(widget.cardColor, widget.textColor, widget.subTextColor),
    );
  }
}

class _StatGraphPainter extends CustomPainter {
  final List<List<double>> series;
  final List<Color> colors;
  final _ChartKind kind;

  _StatGraphPainter(this.series, this.colors, [this.kind = _ChartKind.line]);

  Color _colorAt(int i) => i < colors.length ? colors[i] : const Color(0xFF50A2E9);

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    var maxLen = 0;
    for (final s in series) {
      if (s.length > maxLen) maxLen = s.length;
    }
    if (maxLen < 1) return;

    // Horizontal guide lines.
    final guide = Paint()
      ..color = const Color(0x22808080)
      ..strokeWidth = 1;
    for (var g = 0; g <= 4; g++) {
      final y = size.height * g / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), guide);
    }

    switch (kind) {
      case _ChartKind.bar:
      case _ChartKind.stackedBar:
        _paintBars(canvas, size, maxLen);
        break;
      case _ChartKind.stackedArea:
        _paintStackedArea(canvas, size, maxLen);
        break;
      case _ChartKind.line:
        _paintLines(canvas, size);
        break;
    }
  }

  void _paintLines(Canvas canvas, Size size) {
    double minY = double.infinity, maxY = -double.infinity;
    for (final s in series) {
      for (final v in s) {
        if (v < minY) minY = v;
        if (v > maxY) maxY = v;
      }
    }
    if (!minY.isFinite || !maxY.isFinite) return;
    if (maxY == minY) maxY = minY + 1;
    for (var si = 0; si < series.length; si++) {
      final s = series[si];
      if (s.length < 2) continue;
      final paint = Paint()
        ..color = _colorAt(si)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      final path = Path();
      for (var i = 0; i < s.length; i++) {
        final x = size.width * i / (s.length - 1);
        final y = size.height - (s[i] - minY) / (maxY - minY) * size.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  // Stacked vertical bars: each x sums its series into stacked segments.
  void _paintBars(Canvas canvas, Size size, int maxLen) {
    double maxSum = 0;
    for (var i = 0; i < maxLen; i++) {
      double sum = 0;
      for (final s in series) {
        if (i < s.length) sum += s[i];
      }
      if (sum > maxSum) maxSum = sum;
    }
    if (maxSum <= 0) maxSum = 1;
    final slot = size.width / maxLen;
    final barW = slot * 0.8;
    for (var i = 0; i < maxLen; i++) {
      var yTop = size.height;
      final x = i * slot + (slot - barW) / 2;
      for (var si = 0; si < series.length; si++) {
        final s = series[si];
        if (i >= s.length) continue;
        final h = s[i] / maxSum * size.height;
        if (h <= 0) continue;
        canvas.drawRect(
          Rect.fromLTWH(x, yTop - h, barW, h),
          Paint()..color = _colorAt(si),
        );
        yTop -= h;
      }
    }
  }

  // Stacked filled areas (percentage-style stacking).
  void _paintStackedArea(Canvas canvas, Size size, int maxLen) {
    if (maxLen < 2) return;
    double maxSum = 0;
    for (var i = 0; i < maxLen; i++) {
      double sum = 0;
      for (final s in series) {
        if (i < s.length) sum += s[i];
      }
      if (sum > maxSum) maxSum = sum;
    }
    if (maxSum <= 0) maxSum = 1;
    final cumulative = List<double>.filled(maxLen, 0);
    for (var si = 0; si < series.length; si++) {
      final s = series[si];
      final path = Path();
      // top edge (cumulative + current), left→right
      for (var i = 0; i < maxLen; i++) {
        final v = i < s.length ? s[i] : 0;
        final x = size.width * i / (maxLen - 1);
        final y = size.height - (cumulative[i] + v) / maxSum * size.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      // bottom edge (cumulative), right→left
      for (var i = maxLen - 1; i >= 0; i--) {
        final x = size.width * i / (maxLen - 1);
        final y = size.height - cumulative[i] / maxSum * size.height;
        path.lineTo(x, y);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = _colorAt(si).withValues(alpha: 0.75));
      for (var i = 0; i < maxLen; i++) {
        cumulative[i] += i < s.length ? s[i] : 0;
      }
    }
  }

  @override
  bool shouldRepaint(_StatGraphPainter old) => old.series != series || old.kind != kind;
}

// Per-message statistics (AyuGram messageStatistic) — opened by tapping a
// recent post. Shows the message's interaction graphs + public-shares count.
class _MessageStatsScreen extends StatefulWidget {
  final String accountId;
  final String chatId;
  final int msgId;
  const _MessageStatsScreen({required this.accountId, required this.chatId, required this.msgId});

  @override
  State<_MessageStatsScreen> createState() => _MessageStatsScreenState();
}

class _MessageStatsScreenState extends State<_MessageStatsScreen> {
  Map<String, dynamic>? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<EngineService>().getMessageStats(widget.accountId, widget.chatId, widget.msgId);
      if (mounted) setState(() { _data = d; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0E1621) : const Color(0xFFF0F0F0);
    final cardColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Failed to load message statistics:\n$_error',
              style: TextStyle(color: subTextColor, fontSize: 14), textAlign: TextAlign.center),
        ),
      );
    } else {
      final data = _data ?? {};
      final charts = (data['charts'] as List?) ?? const [];
      final forwards = data['public_forwards_count'] as int? ?? 0;
      body = ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          if (forwards > 0)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Public Shares', style: TextStyle(color: subTextColor, fontSize: 13)),
                  Text('$forwards', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          for (final ch in charts.whereType<Map>())
            _StatChartWidget(
              accountId: widget.accountId,
              chart: ch,
              cardColor: cardColor,
              textColor: textColor,
              subTextColor: subTextColor,
            ),
          if (charts.isEmpty && forwards == 0)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: Text('No statistics for this message.',
                  style: TextStyle(color: subTextColor, fontSize: 14))),
            ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        foregroundColor: textColor,
        elevation: 1,
        title: const Text('Message Statistics', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: body,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// Boosts — full section page (AyuGram Info::Boosts): level header, progress,
// premium-audience breakdown and the paginated boosters list.
// ════════════════════════════════════════════════════════════════════════

class _BoostsScreen extends StatefulWidget {
  final String accountId;
  final String chatId;
  final String title;

  const _BoostsScreen({
    required this.accountId,
    required this.chatId,
    required this.title,
  });

  @override
  State<_BoostsScreen> createState() => _BoostsScreenState();
}

class _BoostsScreenState extends State<_BoostsScreen> {
  Map<String, dynamic>? _status;
  Object? _error;
  bool _loadingStatus = true;

  // Two slices — boosts vs gifts (firstSliceBoosts / firstSliceGifts) — switched
  // by a tab, mirroring info_boosts_inner_widget.cpp:455.
  bool _showGifts = false;
  final List<Map<String, dynamic>> _boosters = [];
  final List<Map<String, dynamic>> _gifts = [];
  String _offset = '';
  String _giftsOffset = '';
  int _total = 0;
  int _giftsTotal = 0;
  bool _loadingMore = false;
  bool _loadingGifts = false;
  bool _hasMore = true;
  bool _giftsHasMore = true;
  bool _giftsLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _loadMoreBoosters();
  }

  Future<void> _loadStatus() async {
    final engine = context.read<EngineService>();
    try {
      final s = await engine.getBoosts(widget.accountId, widget.chatId);
      if (mounted) setState(() { _status = s; _loadingStatus = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loadingStatus = false; });
    }
  }

  Future<void> _loadMoreBoosters() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final engine = context.read<EngineService>();
    try {
      final res = await engine.getBoostsList(widget.accountId, widget.chatId, offset: _offset);
      final list = (res['boosters'] as List?) ?? const [];
      final next = res['next_offset'] as String? ?? '';
      if (mounted) {
        setState(() {
          _total = res['count'] as int? ?? _total;
          _boosters.addAll(list.whereType<Map>().map((e) => e.cast<String, dynamic>()));
          _offset = next;
          _hasMore = next.isNotEmpty && list.isNotEmpty;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loadingMore = false; _hasMore = false; });
    }
  }

  Future<void> _loadMoreGifts() async {
    if (_loadingGifts || !_giftsHasMore) return;
    setState(() { _loadingGifts = true; _giftsLoadedOnce = true; });
    final engine = context.read<EngineService>();
    try {
      final res = await engine.getBoostsList(widget.accountId, widget.chatId, isGifts: true, offset: _giftsOffset);
      final list = (res['boosters'] as List?) ?? const [];
      final next = res['next_offset'] as String? ?? '';
      if (mounted) {
        setState(() {
          _giftsTotal = res['count'] as int? ?? _giftsTotal;
          _gifts.addAll(list.whereType<Map>().map((e) => e.cast<String, dynamic>()));
          _giftsOffset = next;
          _giftsHasMore = next.isNotEmpty && list.isNotEmpty;
          _loadingGifts = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loadingGifts = false; _giftsHasMore = false; });
    }
  }

  void _openGiveaway() {
    final prepaid = _status?['prepaid_giveaways'];
    final prepaidList = prepaid is List ? prepaid.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
    showCreateGiveawayBox(
      context,
      accountId: widget.accountId,
      chatId: widget.chatId,
      theme: Theme.of(context),
      prepaidGiveaways: prepaidList,
    );
  }

  static String _fmtDate(int epochSec) {
    if (epochSec <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0E1621) : const Color(0xFFF0F0F0);
    final cardColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    final accentColor = PaletteProvider.of(context).windowBgActive;

    final data = _status ?? {};
    final level = data['my_boost_level'] as int? ?? data['level'] as int? ?? 0;
    final boosts = data['boosts'] as int? ?? 0;
    final currentLevelBoosts = data['current_level_boosts'] as int? ?? 0;
    final nextLevelBoosts = data['next_level_boosts'] as int? ?? 0;
    final premiumAudience = data['premium_audience'] as Map? ?? const {};

    double progress = 0;
    if (nextLevelBoosts > currentLevelBoosts) {
      progress = (boosts - currentLevelBoosts) / (nextLevelBoosts - currentLevelBoosts);
      progress = progress.clamp(0.0, 1.0);
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        foregroundColor: textColor,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Boosts', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            Text(widget.title, style: TextStyle(fontSize: 12, color: subTextColor)),
          ],
        ),
      ),
      body: _loadingStatus
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Failed to load boosts:\n$_error',
                        style: TextStyle(color: subTextColor, fontSize: 14), textAlign: TextAlign.center),
                  ),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
                      if (_showGifts) {
                        _loadMoreGifts();
                      } else {
                        _loadMoreBoosters();
                      }
                    }
                    return false;
                  },
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    children: [
                      // Level + progress header.
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          children: [
                            Text('Level $level',
                                style: TextStyle(color: accentColor, fontSize: 26, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('$boosts ${boosts == 1 ? 'boost' : 'boosts'}',
                                style: TextStyle(color: textColor, fontSize: 15)),
                            if (nextLevelBoosts > 0) ...[
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 8,
                                  backgroundColor: subTextColor.withValues(alpha: 0.2),
                                  valueColor: AlwaysStoppedAnimation(accentColor),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text('$boosts / $nextLevelBoosts for Level ${level + 1}',
                                  style: TextStyle(color: subTextColor, fontSize: 12)),
                            ],
                          ],
                        ),
                      ),
                      if (premiumAudience.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                          child: Text(
                            'Premium audience: ${((premiumAudience['part'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}%',
                            style: TextStyle(color: subTextColor, fontSize: 13),
                          ),
                        ),
                      // Invite/share-link block (FillShareLink) — copy/share the
                      // boost link (info_boosts_inner_widget.cpp:341).
                      if ((data['boost_url'] as String? ?? '').isNotEmpty)
                        _buildShareLink(data['boost_url'] as String, cardColor, textColor, subTextColor, accentColor),
                      // Prepaid giveaway rows.
                      ..._buildPrepaidGiveaways(data, cardColor, textColor, subTextColor, accentColor),
                      // Boosts / Gifts tab switcher.
                      _buildSliceTabs(cardColor, textColor, subTextColor, accentColor),
                      // Active slice list.
                      if (_showGifts) ...[
                        if (_gifts.isEmpty && !_loadingGifts && _giftsLoadedOnce)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Text('No gifted boosts yet.', style: TextStyle(color: subTextColor, fontSize: 14)),
                          ),
                        ..._gifts.map((b) => _BoosterRow(
                              booster: b,
                              cardColor: cardColor,
                              textColor: textColor,
                              subTextColor: subTextColor,
                              accentColor: accentColor,
                              dateText: _fmtDate(b['expires'] as int? ?? 0),
                            )),
                        if (_loadingGifts)
                          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
                      ] else ...[
                        if (_boosters.isEmpty && !_loadingMore)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Text('No boosters yet.', style: TextStyle(color: subTextColor, fontSize: 14)),
                          ),
                        ..._boosters.map((b) => _BoosterRow(
                              booster: b,
                              cardColor: cardColor,
                              textColor: textColor,
                              subTextColor: subTextColor,
                              accentColor: accentColor,
                              dateText: _fmtDate(b['expires'] as int? ?? 0),
                            )),
                        if (_loadingMore)
                          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
                      ],
                      // Create-giveaway / "Get Boosts via Gifts" button
                      // (FillGetBoostsButton → CreateGiveawayBox).
                      _buildGiveawayButton(accentColor),
                    ],
                  ),
                ),
    );
  }

  Widget _buildShareLink(String url, Color cardColor, Color textColor, Color subTextColor, Color accentColor) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 14, 12, 2),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Share this link to boost', style: TextStyle(color: subTextColor, fontSize: 13)),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: url));
              showTelegramToast(context, 'Link copied');
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accentColor.withValues(alpha: 0.3)),
              ),
              child: Text(url.replaceFirst('https://', ''),
                  style: TextStyle(color: accentColor, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    showTelegramToast(context, 'Link copied');
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Share.share(url),
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Share'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPrepaidGiveaways(
      Map data, Color cardColor, Color textColor, Color subTextColor, Color accentColor) {
    final prepaid = (data['prepaid_giveaways'] as List?) ?? const [];
    if (prepaid.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text('Prepaid Giveaways',
            style: TextStyle(color: subTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
      ...prepaid.whereType<Map>().map((g) {
        final quantity = (g['quantity'] as num?)?.toInt() ?? 0;
        final months = (g['months'] as num?)?.toInt() ?? 0;
        return InkWell(
          onTap: _openGiveaway,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                CircleAvatar(radius: 18, backgroundColor: accentColor, child: const Icon(Icons.card_giftcard, color: Colors.white, size: 18)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$quantity Telegram Premium', style: TextStyle(color: textColor, fontSize: 14)),
                      Text('$months ${months == 1 ? 'month' : 'months'}', style: TextStyle(color: subTextColor, fontSize: 12)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: subTextColor),
              ],
            ),
          ),
        );
      }),
    ];
  }

  Widget _buildSliceTabs(Color cardColor, Color textColor, Color subTextColor, Color accentColor) {
    Widget tab(String label, bool selected, VoidCallback onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: [
                  Text(label,
                      style: TextStyle(
                          color: selected ? accentColor : subTextColor,
                          fontSize: 14,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
                  const SizedBox(height: 6),
                  Container(height: 2, color: selected ? accentColor : Colors.transparent),
                ],
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          tab(_total > 0 ? 'Boosts · $_total' : 'Boosts', !_showGifts, () => setState(() => _showGifts = false)),
          tab(_giftsTotal > 0 ? 'Gifts · $_giftsTotal' : 'Gifts', _showGifts, () {
            setState(() => _showGifts = true);
            if (!_giftsLoadedOnce) _loadMoreGifts();
          }),
        ],
      ),
    );
  }

  Widget _buildGiveawayButton(Color accentColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _openGiveaway,
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.card_giftcard, size: 20),
          label: const Text('Get Boosts via Gifts'),
        ),
      ),
    );
  }
}

class _BoosterRow extends StatelessWidget {
  final Map<String, dynamic> booster;
  final Color cardColor;
  final Color textColor;
  final Color subTextColor;
  final Color accentColor;
  final String dateText;

  const _BoosterRow({
    required this.booster,
    required this.cardColor,
    required this.textColor,
    required this.subTextColor,
    required this.accentColor,
    required this.dateText,
  });

  @override
  Widget build(BuildContext context) {
    final name = (booster['user_name'] as String?)?.trim();
    final isGiveaway = booster['giveaway'] == true;
    final isGift = booster['gift'] == true;
    final isUnclaimed = booster['unclaimed'] == true;
    final multiplier = booster['multiplier'] as int? ?? 0;
    final displayName = (name != null && name.isNotEmpty)
        ? name
        : (isUnclaimed ? 'Unclaimed' : (isGiveaway ? 'Giveaway' : 'Unknown'));
    final letter = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    final badges = <String>[];
    if (isGiveaway) badges.add('Giveaway');
    if (isGift) badges.add('Gift');

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: accentColor.withValues(alpha: 0.85),
            child: Text(letter, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName,
                    style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (dateText.isNotEmpty)
                  Text('Expires $dateText', style: TextStyle(color: subTextColor, fontSize: 12)),
              ],
            ),
          ),
          if (badges.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(badges.join(' · '),
                  style: TextStyle(color: accentColor, fontSize: 11, fontWeight: FontWeight.w500)),
            ),
          if (multiplier > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('×$multiplier',
                  style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

// Channel Earn (Stars revenue) overview — AyuGram's Info::ChannelEarn section.
// Shows the real Stars balance overview from payments.getStarsRevenueStats
// (current/available/overall + USD conversion) instead of a raw key:value dump.
class _MonetizationScreen extends StatefulWidget {
  final String accountId;
  final String chatId;
  final String title;

  const _MonetizationScreen({
    required this.accountId,
    required this.chatId,
    required this.title,
  });

  @override
  State<_MonetizationScreen> createState() => _MonetizationScreenState();
}

class _MonetizationScreenState extends State<_MonetizationScreen> {
  Map<String, dynamic>? _stats;
  Object? _error;
  bool _loading = true;
  bool _withdrawing = false;

  final List<Map<String, dynamic>> _transactions = [];
  String _txOffset = '';
  bool _txHasMore = true;
  bool _loadingTx = false;
  bool _txLoadedOnce = false;

  // TON (currency) ad-revenue — the currency side of AyuGram's earn section,
  // shown before the Stars/credits side (info_channel_earn_list.cpp:611).
  Map<String, dynamic>? _tonStats;
  bool _tonWithdrawing = false;
  final List<Map<String, dynamic>> _tonTransactions = [];
  String _tonTxOffset = '';
  bool _tonTxHasMore = true;
  bool _loadingTonTx = false;
  bool _tonTxLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final engine = context.read<EngineService>();
    // Fetch the TON (currency) revenue first — it's shown above the Stars
    // section. A megagroup without broadcast rights returns BROADCAST_REQUIRED;
    // treat any failure/empty as "no currency revenue" and just hide the section.
    try {
      final ton = await engine.getBroadcastRevenueStats(widget.accountId, widget.chatId);
      if (mounted && ton != null) {
        setState(() => _tonStats = ton);
        if (_tonHasAny(ton)) _loadMoreTonTransactions();
      }
    } catch (_) {}
    try {
      final s = await engine.getStarsRevenueStats(widget.accountId, widget.chatId);
      if (mounted) setState(() { _stats = s; _loading = false; });
      _loadMoreTransactions();
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  static bool _tonHasAny(Map<String, dynamic> ton) {
    final available = ton['available_balance'] as int? ?? 0;
    final current = ton['current_balance'] as int? ?? 0;
    final overall = ton['overall_revenue'] as int? ?? 0;
    final charts = (ton['charts'] as List?) ?? const [];
    return available != 0 || current != 0 || overall != 0 || charts.isNotEmpty;
  }

  Future<void> _loadMoreTonTransactions() async {
    if (_loadingTonTx || !_tonTxHasMore) return;
    setState(() { _loadingTonTx = true; _tonTxLoadedOnce = true; });
    final engine = context.read<EngineService>();
    try {
      final res = await engine.getBroadcastRevenueTransactions(widget.accountId, widget.chatId, offset: _tonTxOffset);
      final list = (res['transactions'] as List?) ?? const [];
      final next = res['next_offset'] as String? ?? '';
      if (mounted) {
        setState(() {
          _tonTransactions.addAll(list.whereType<Map>().map((e) => e.cast<String, dynamic>()));
          _tonTxOffset = next;
          _tonTxHasMore = next.isNotEmpty && list.isNotEmpty;
          _loadingTonTx = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loadingTonTx = false; _tonTxHasMore = false; });
    }
  }

  // TON withdraw flow: collect the 2FA password, fetch the withdrawal URL, open
  // it (Api::HandleWithdrawalButton, currency/ton path).
  Future<void> _withdrawTon() async {
    if (_tonWithdrawing) return;
    final password = await _promptPassword(isTon: true);
    if (password == null || password.isEmpty || !mounted) return;
    setState(() => _tonWithdrawing = true);
    final engine = context.read<EngineService>();
    try {
      final url = await engine.getBroadcastRevenueWithdrawalUrl(widget.accountId, widget.chatId, password);
      if (!mounted) return;
      setState(() => _tonWithdrawing = false);
      if (url.isEmpty) {
        showTelegramToast(context, 'Withdrawal unavailable');
        return;
      }
      final uri = Uri.tryParse(url);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) showTelegramToast(context, 'Withdrawal link copied');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _tonWithdrawing = false);
        showTelegramToast(context, 'Withdrawal failed: $e');
      }
    }
  }

  // nanotons → "X.YY" (integer whole part + 2 decimal digits, no rounding),
  // matching AyuGram MajorPart/MinorPart for currency (earn_format.cpp).
  static String _fmtTon(int nanotons) {
    final neg = nanotons < 0;
    final abs = nanotons.abs();
    final whole = abs ~/ 1000000000;
    final frac2 = (abs % 1000000000) ~/ 10000000;
    final s = '$whole.${frac2.toString().padLeft(2, '0')}';
    return neg ? '-$s' : s;
  }

  // For TON, usd_rate is the value of 1 TON in USD (AyuGram ToUsd: value*rate,
  // value = nanotons/1e9), unlike Stars where it's per-1000.
  static String _fmtUsdTon(int nanotons, double usdRate) {
    if (usdRate <= 0) return '';
    final usd = (nanotons / 1e9) * usdRate;
    return '≈ \$${usd.toStringAsFixed(2)}';
  }

  Future<void> _loadMoreTransactions() async {
    if (_loadingTx || !_txHasMore) return;
    setState(() { _loadingTx = true; _txLoadedOnce = true; });
    final engine = context.read<EngineService>();
    try {
      final res = await engine.getChannelStarsTransactions(widget.accountId, widget.chatId, offset: _txOffset);
      final list = (res['transactions'] as List?) ?? const [];
      final next = res['next_offset'] as String? ?? '';
      if (mounted) {
        setState(() {
          _transactions.addAll(list.whereType<Map>().map((e) => e.cast<String, dynamic>()));
          _txOffset = next;
          _txHasMore = next.isNotEmpty && list.isNotEmpty;
          _loadingTx = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loadingTx = false; _txHasMore = false; });
    }
  }

  // Withdraw flow: collect the 2FA password, fetch the withdrawal URL, open it.
  Future<void> _withdraw() async {
    if (_withdrawing) return;
    final password = await _promptPassword();
    if (password == null || password.isEmpty || !mounted) return;
    setState(() => _withdrawing = true);
    final engine = context.read<EngineService>();
    try {
      final url = await engine.getStarsRevenueWithdrawalUrl(widget.accountId, widget.chatId, password);
      if (!mounted) return;
      setState(() => _withdrawing = false);
      if (url.isEmpty) {
        showTelegramToast(context, 'Withdrawal unavailable');
        return;
      }
      final uri = Uri.tryParse(url);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) showTelegramToast(context, 'Withdrawal link copied');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _withdrawing = false);
        showTelegramToast(context, 'Withdrawal failed: $e');
      }
    }
  }

  Future<String?> _promptPassword({bool isTon = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    final accentColor = PaletteProvider.of(context).windowBgActive;
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('Confirm Withdrawal', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isTon
                ? 'Enter your 2FA password to withdraw your TON balance.'
                : 'Enter your 2FA password to withdraw your Stars balance.',
                style: TextStyle(color: subTextColor, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              autofocus: true,
              style: TextStyle(color: textColor, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Password',
                border: const UnderlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: subTextColor))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text('Withdraw', style: TextStyle(color: accentColor, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // usd_rate is the value of 1000 Stars in USD (matches _showRevenueStats).
  static String _fmtUsd(int stars, double usdRate) {
    if (usdRate <= 0) return '';
    final usd = stars * usdRate / 1000;
    return '≈ \$${usd.toStringAsFixed(2)}';
  }

  static String _txDate(int epochSec) {
    if (epochSec <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildTransactionRow(
      Map<String, dynamic> tx, Color cardColor, Color textColor, Color subTextColor, Color starColor) {
    final amount = (tx['amount'] as num?)?.toInt() ?? 0;
    final refund = tx['refund'] == true;
    final title = (tx['title'] as String?)?.trim() ?? '';
    final desc = (tx['description'] as String?)?.trim() ?? '';
    final date = tx['date'] as int? ?? 0;
    final incoming = amount >= 0;
    final label = title.isNotEmpty ? title : (desc.isNotEmpty ? desc : (incoming ? 'Proceeds' : 'Withdrawal'));
    final amountColor = refund
        ? subTextColor
        : (incoming ? const Color(0xFF4FAD2D) : const Color(0xFFE53935));
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(refund ? '$label (refund)' : label,
                    style: TextStyle(color: textColor, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (date > 0) ...[
                  const SizedBox(height: 2),
                  Text(_txDate(date), style: TextStyle(color: subTextColor, fontSize: 12)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.star, size: 15, color: starColor),
          const SizedBox(width: 3),
          Text('${incoming ? '+' : ''}$amount',
              style: TextStyle(color: amountColor, fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // TON (currency) revenue transaction row — amount is signed nanotons, rendered
  // as ±X.YY TON with the diamond glyph (info_channel_earn_list.cpp history list).
  Widget _buildTonTransactionRow(
      Map<String, dynamic> tx, Color cardColor, Color textColor, Color subTextColor, double usdRate) {
    const tonColor = Color(0xFF0098EA);
    final amount = (tx['amount'] as num?)?.toInt() ?? 0;
    final refund = tx['refund'] == true;
    final pending = tx['pending'] == true;
    final failed = tx['failed'] == true;
    final title = (tx['title'] as String?)?.trim() ?? '';
    final desc = (tx['description'] as String?)?.trim() ?? '';
    final date = tx['date'] as int? ?? 0;
    final incoming = amount >= 0;
    final label = title.isNotEmpty ? title : (desc.isNotEmpty ? desc : (incoming ? 'Proceeds' : 'Withdrawal'));
    final amountColor = (refund || pending)
        ? subTextColor
        : failed
            ? const Color(0xFFE53935)
            : (incoming ? const Color(0xFF4FAD2D) : const Color(0xFFE53935));
    final sub = failed
        ? 'Failed'
        : pending
            ? 'Pending'
            : _txDate(date);
    final usd = _fmtUsdTon(amount, usdRate);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(refund ? '$label (refund)' : label,
                    style: TextStyle(color: textColor, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(color: subTextColor, fontSize: 12)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.diamond, size: 14, color: tonColor),
                  const SizedBox(width: 3),
                  Text('${incoming ? '+' : ''}${_fmtTon(amount)}',
                      style: TextStyle(color: amountColor, fontSize: 15, fontWeight: FontWeight.w700)),
                ],
              ),
              if (usd.isNotEmpty)
                Text(usd, style: TextStyle(color: subTextColor.withValues(alpha: 0.7), fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0E1621) : const Color(0xFFF0F0F0);
    final cardColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    final accentColor = PaletteProvider.of(context).windowBgActive;
    const starColor = Color(0xFFFFB800);

    final data = _stats ?? const {};
    final available = data['available_balance'] as int? ?? 0;
    final current = data['current_balance'] as int? ?? 0;
    final overall = data['overall_revenue'] as int? ?? 0;
    final withdrawalEnabled = data['withdrawal_enabled'] as bool? ?? false;
    final usdRate = (data['usd_rate'] as num?)?.toDouble() ?? 0.0;

    Widget balanceTile(String label, int stars, {bool emphasize = false}) {
      final usd = _fmtUsd(stars, usdRate);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 13, color: subTextColor)),
                  if (usd.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(usd, style: TextStyle(fontSize: 12, color: subTextColor.withValues(alpha: 0.7))),
                  ],
                ],
              ),
            ),
            const Icon(Icons.star, size: 18, color: starColor),
            const SizedBox(width: 4),
            Text(
              '$stars',
              style: TextStyle(
                fontSize: emphasize ? 20 : 16,
                fontWeight: FontWeight.w700,
                color: emphasize ? accentColor : textColor,
              ),
            ),
          ],
        ),
      );
    }

    // ── TON (currency) ad-revenue ── shown BEFORE the Stars section, matching
    // AyuGram (currency THEN credits — info_channel_earn_list.cpp:611,930).
    const tonColor = Color(0xFF0098EA);
    final tonData = _tonStats ?? const {};
    final tonAvailable = tonData['available_balance'] as int? ?? 0; // nanotons
    final tonCurrent = tonData['current_balance'] as int? ?? 0;
    final tonOverall = tonData['overall_revenue'] as int? ?? 0;
    final tonWithdrawalEnabled = tonData['withdrawal_enabled'] as bool? ?? false;
    final tonUsdRate = (tonData['usd_rate'] as num?)?.toDouble() ?? 0.0;
    final tonCharts = (tonData['charts'] as List?) ?? const [];
    final hasTon = _tonStats != null &&
        (tonAvailable != 0 ||
            tonCurrent != 0 ||
            tonOverall != 0 ||
            tonCharts.isNotEmpty ||
            _tonTransactions.isNotEmpty);

    Widget tonBalanceTile(String label, int nanotons, {bool emphasize = false}) {
      final usd = _fmtUsdTon(nanotons, tonUsdRate);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 13, color: subTextColor)),
                  if (usd.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(usd, style: TextStyle(fontSize: 12, color: subTextColor.withValues(alpha: 0.7))),
                  ],
                ],
              ),
            ),
            const Icon(Icons.diamond, size: 18, color: tonColor),
            const SizedBox(width: 4),
            Text(
              _fmtTon(nanotons),
              style: TextStyle(
                fontSize: emphasize ? 20 : 16,
                fontWeight: FontWeight.w700,
                color: emphasize ? accentColor : textColor,
              ),
            ),
          ],
        ),
      );
    }

    List<Widget> tonSection() {
      if (!hasTon) return const [];
      return [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                child: Row(
                  children: [
                    const Icon(Icons.diamond, size: 16, color: tonColor),
                    const SizedBox(width: 6),
                    Text('TON Balance',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accentColor)),
                  ],
                ),
              ),
              tonBalanceTile('Available to withdraw', tonAvailable, emphasize: true),
              Divider(height: 1, color: bgColor),
              tonBalanceTile('Current balance', tonCurrent),
              Divider(height: 1, color: bgColor),
              tonBalanceTile('Total lifetime revenue', tonOverall),
              const SizedBox(height: 6),
            ],
          ),
        ),
        // TON withdraw button (Api::HandleWithdrawalButton, currency/ton path).
        if (tonWithdrawalEnabled && tonAvailable > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _tonWithdrawing ? null : _withdrawTon,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _tonWithdrawing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.account_balance_wallet_outlined, size: 20),
                label: Text(_tonWithdrawing ? 'Processing…' : 'Withdraw TON'),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Text(
            'You earn Toncoin from ads displayed in this channel. Once your balance '
            'reaches the minimum, you can withdraw it to your TON wallet.',
            style: TextStyle(fontSize: 12, color: subTextColor, height: 1.4),
          ),
        ),
        // TON revenue + top-hours charts (info_channel_earn_list.cpp:621-648).
        ...(() {
          if (tonCharts.isEmpty) return <Widget>[];
          return [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text('TON Revenue',
                  style: TextStyle(color: subTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            ...tonCharts.whereType<Map>().map((ch) => _StatChartWidget(
                  accountId: widget.accountId,
                  chart: ch,
                  cardColor: cardColor,
                  textColor: textColor,
                  subTextColor: subTextColor,
                )),
          ];
        })(),
        // TON transaction history (info_channel_earn_list.cpp:1288 currency tab).
        if (_tonTransactions.isNotEmpty || _loadingTonTx) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text('TON Transactions',
                style: TextStyle(color: subTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          ..._tonTransactions.map((tx) => _buildTonTransactionRow(tx, cardColor, textColor, subTextColor, tonUsdRate)),
          if (_tonTxHasMore)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Center(
                child: _loadingTonTx
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton(onPressed: _loadMoreTonTransactions, child: Text('Show more', style: TextStyle(color: accentColor))),
              ),
            ),
        ],
        // Separator before the Stars (credits) section.
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Divider(height: 1, color: subTextColor.withValues(alpha: 0.2)),
        ),
        const SizedBox(height: 6),
      ];
    }

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Failed to load earnings:\n$_error',
              style: TextStyle(color: subTextColor, fontSize: 14), textAlign: TextAlign.center),
        ),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // Currency (TON) section first, then the Stars (credits) section.
          ...tonSection(),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                  child: Text('Stars Balance',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accentColor)),
                ),
                balanceTile('Available to withdraw', available, emphasize: true),
                Divider(height: 1, color: bgColor),
                balanceTile('Current balance', current),
                Divider(height: 1, color: bgColor),
                balanceTile('Total lifetime revenue', overall),
                const SizedBox(height: 6),
              ],
            ),
          ),
          // Withdraw button (Api::HandleWithdrawalButton → AddWithdrawalWidget).
          if (withdrawalEnabled && available > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _withdrawing ? null : _withdraw,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _withdrawing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.account_balance_wallet_outlined, size: 20),
                  label: Text(_withdrawing ? 'Processing…' : 'Withdraw'),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              'You earn Stars from paid reactions, paid messages and other paid '
              'content in this channel. Stars can be converted to Toncoin and '
              'withdrawn once the balance reaches the minimum.',
              style: TextStyle(fontSize: 12, color: subTextColor, height: 1.4),
            ),
          ),
          // Revenue + top-hours graphs (info_channel_earn_list.cpp:611).
          ...(() {
            final charts = (data['charts'] as List?) ?? const [];
            if (charts.isEmpty) return <Widget>[];
            return [
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text('Revenue',
                    style: TextStyle(color: subTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              ...charts.whereType<Map>().map((ch) => _StatChartWidget(
                    accountId: widget.accountId,
                    chart: ch,
                    cardColor: cardColor,
                    textColor: textColor,
                    subTextColor: subTextColor,
                  )),
            ];
          })(),
          // Transaction history (info_channel_earn_list.cpp:1288).
          if (_transactions.isNotEmpty || _loadingTx) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text('Transactions',
                  style: TextStyle(color: subTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            ..._transactions.map((tx) => _buildTransactionRow(tx, cardColor, textColor, subTextColor, starColor)),
            if (_txHasMore)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Center(
                  child: _loadingTx
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : TextButton(onPressed: _loadMoreTransactions, child: Text('Show more', style: TextStyle(color: accentColor))),
                ),
              ),
          ] else if (_txLoadedOnce)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text('No transactions yet.', style: TextStyle(color: subTextColor, fontSize: 13)),
            ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        foregroundColor: textColor,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Monetization', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            Text(widget.title, style: TextStyle(fontSize: 12, color: subTextColor)),
          ],
        ),
      ),
      body: body,
    );
  }
}

// ── Star-ref (affiliate program) JOIN flow ──
// A broadcast channel joins other bots' affiliate programs to advertise them and
// earn star commissions (info_bot_starref_join_widget.cpp). It cannot own a
// program — that setup flow is bot-only.
class _StarRefJoinScreen extends StatefulWidget {
  final String accountId;
  final String chatId;
  final String title;
  const _StarRefJoinScreen({required this.accountId, required this.chatId, required this.title});

  @override
  State<_StarRefJoinScreen> createState() => _StarRefJoinScreenState();
}

class _StarRefJoinScreenState extends State<_StarRefJoinScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _connected = [];
  List<Map<String, dynamic>> _suggested = [];
  String _nextOffset = '';
  bool _loadingMore = false;
  final Set<String> _connecting = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final engine = context.read<EngineService>();
    try {
      final connected = await engine.getConnectedStarRefBots(widget.accountId, widget.chatId);
      final suggested = await engine.getSuggestedStarRefBots(widget.accountId, widget.chatId);
      if (!mounted) return;
      setState(() {
        _connected = connected;
        _suggested = (suggested['bots'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _nextOffset = suggested['next_offset'] as String? ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _nextOffset.isEmpty) return;
    setState(() => _loadingMore = true);
    final engine = context.read<EngineService>();
    try {
      final more = await engine.getSuggestedStarRefBots(widget.accountId, widget.chatId, offset: _nextOffset);
      if (!mounted) return;
      setState(() {
        _suggested.addAll((more['bots'] as List?)?.cast<Map<String, dynamic>>() ?? []);
        _nextOffset = more['next_offset'] as String? ?? '';
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _connect(Map<String, dynamic> bot) async {
    final botId = bot['bot_id'] as String? ?? '';
    if (botId.isEmpty || _connecting.contains(botId)) return;
    setState(() => _connecting.add(botId));
    final engine = context.read<EngineService>();
    try {
      final result = await engine.connectStarRefBot(widget.accountId, widget.chatId, botId);
      if (!mounted) return;
      setState(() {
        _connecting.remove(botId);
        if (result.isNotEmpty) {
          _connected.insert(0, result);
          _suggested.removeWhere((b) => b['bot_id'] == botId);
        }
      });
      final url = result['url'] as String? ?? '';
      if (url.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) showTelegramToast(context, 'Joined — referral link copied');
      } else if (mounted) {
        showTelegramToast(context, 'Joined affiliate program');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _connecting.remove(botId));
        showTelegramToast(context, 'Failed: $e');
      }
    }
  }

  String _commission(Map<String, dynamic> b) {
    final permille = (b['commission_permille'] as num?)?.toInt() ?? 0;
    return '${(permille / 10).toStringAsFixed(permille % 10 == 0 ? 0 : 1)}%';
  }

  String _duration(Map<String, dynamic> b) {
    final m = (b['duration_months'] as num?)?.toInt() ?? 0;
    if (m == 0) return 'Lifetime';
    if (m % 12 == 0) return '${m ~/ 12}y';
    return '${m}mo';
  }

  @override
  Widget build(BuildContext context) {
    final palette = PaletteProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0E1621) : const Color(0xFFE6EBF0);
    final cardColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    final accentColor = palette.windowBgActive;

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(_error!, style: TextStyle(color: palette.attentionButtonFg)),
        ),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Earn Telegram Stars by advertising other bots in your channel. '
              'Join a program below to get your referral link.',
              style: TextStyle(color: subTextColor, fontSize: 13),
            ),
          ),
          if (_connected.isNotEmpty) ...[
            _sectionHeader('My Programs', accentColor),
            for (final b in _connected)
              _ConnectedStarRefRow(
                bot: b,
                cardColor: cardColor,
                textColor: textColor,
                subTextColor: subTextColor,
                accentColor: accentColor,
                commission: _commission(b),
                duration: _duration(b),
              ),
          ],
          if (_suggested.isNotEmpty) ...[
            _sectionHeader('Existing Programs', accentColor),
            for (final b in _suggested)
              _SuggestedStarRefRow(
                bot: b,
                cardColor: cardColor,
                textColor: textColor,
                subTextColor: subTextColor,
                accentColor: accentColor,
                commission: _commission(b),
                duration: _duration(b),
                connecting: _connecting.contains(b['bot_id']),
                onConnect: () => _connect(b),
              ),
            if (_nextOffset.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: _loadingMore
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : TextButton(onPressed: _loadMore, child: Text('Show more', style: TextStyle(color: accentColor))),
                ),
              ),
          ],
          if (_connected.isEmpty && _suggested.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text('No affiliate programs available.',
                    style: TextStyle(color: subTextColor, fontSize: 14)),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        foregroundColor: textColor,
        elevation: 1,
        title: const Text('Affiliate Program', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: body,
    );
  }

  Widget _sectionHeader(String title, Color accentColor) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(title.toUpperCase(),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: accentColor)),
      );
}

class _ConnectedStarRefRow extends StatelessWidget {
  final Map<String, dynamic> bot;
  final Color cardColor, textColor, subTextColor, accentColor;
  final String commission, duration;
  const _ConnectedStarRefRow({
    required this.bot,
    required this.cardColor,
    required this.textColor,
    required this.subTextColor,
    required this.accentColor,
    required this.commission,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    final name = (bot['bot_name'] as String?)?.trim();
    final username = bot['bot_username'] as String? ?? '';
    final url = bot['url'] as String? ?? '';
    final revoked = bot['revoked'] == true;
    final display = (name != null && name.isNotEmpty) ? name : (username.isNotEmpty ? '@$username' : 'Bot');
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 3, 12, 3),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: accentColor,
                child: Text(display.isNotEmpty ? display[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(display,
                        style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('$commission · $duration${revoked ? ' · ended' : ''}',
                        style: TextStyle(color: subTextColor, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          if (url.isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: url));
                showTelegramToast(context, 'Referral link copied');
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(url,
                          style: TextStyle(color: accentColor, fontSize: 13),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.copy, size: 18, color: accentColor),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: url));
                        showTelegramToast(context, 'Referral link copied');
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.share, size: 18, color: accentColor),
                      onPressed: () => Share.share(url),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SuggestedStarRefRow extends StatelessWidget {
  final Map<String, dynamic> bot;
  final Color cardColor, textColor, subTextColor, accentColor;
  final String commission, duration;
  final bool connecting;
  final VoidCallback onConnect;
  const _SuggestedStarRefRow({
    required this.bot,
    required this.cardColor,
    required this.textColor,
    required this.subTextColor,
    required this.accentColor,
    required this.commission,
    required this.duration,
    required this.connecting,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final name = (bot['bot_name'] as String?)?.trim();
    final username = bot['bot_username'] as String? ?? '';
    final display = (name != null && name.isNotEmpty) ? name : (username.isNotEmpty ? '@$username' : 'Bot');
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 3, 12, 3),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: accentColor,
            child: Text(display.isNotEmpty ? display[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontSize: 15)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(display,
                    style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('$commission commission · $duration',
                    style: TextStyle(color: subTextColor, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          connecting
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  onPressed: onConnect,
                  style: TextButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  ),
                  child: const Text('Join'),
                ),
        ],
      ),
    );
  }
}
