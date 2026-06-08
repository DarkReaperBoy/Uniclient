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
import 'package:uniclient/utils/debug.dart';

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

/// Mirrors AyuGram `Ui::ToggleTopicsBox` (boxes/peers/toggle_topics_box.cpp):
/// an Enable-topics switch plus, when on, a Tabs/List layout chooser. The Save
/// button hands both values to [onSave]; the caller queues them for its own
/// Save pipeline rather than applying immediately.
Future<void> showToggleTopicsBox(
  BuildContext context, {
  required bool enabled,
  required bool tabs,
  required void Function(bool enabled, bool tabs) onSave,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
  final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
  final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
  final accentColor = PaletteProvider.of(context).windowBgActive;
  bool localEnabled = enabled;
  bool localTabs = tabs;

  return showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Widget layoutButton(bool isTabs, IconData icon, String label) {
          final active = localTabs == isTabs;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setLocal(() => localTabs = isTabs),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  children: [
                    Icon(icon, size: 34, color: active ? accentColor : subTextColor),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: active ? accentColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(label,
                          style: TextStyle(
                              fontSize: 13,
                              color: active ? Colors.white : subTextColor,
                              fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return AlertDialog(
          backgroundColor: bgColor,
          title: Text('Topics', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Topics let members start separate discussions on different subjects.',
                  style: TextStyle(color: subTextColor, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text('Enable Topics',
                          style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                    Switch(
                      value: localEnabled,
                      activeColor: accentColor,
                      onChanged: (v) => setLocal(() => localEnabled = v),
                    ),
                  ],
                ),
                if (localEnabled) ...[
                  const Divider(height: 20),
                  Text('LAYOUT',
                      style: TextStyle(color: subTextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      layoutButton(true, Icons.tab, 'Tabs'),
                      layoutButton(false, Icons.view_list, 'List'),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: subTextColor)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                onSave(localEnabled, localTabs);
              },
              child: Text('Save', style: TextStyle(color: accentColor)),
            ),
          ],
        );
      },
    ),
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
  bool _forumTabs = true;
  String _linkedChatId = '';
  String _linkedChatTitle = '';
  bool _hasLocation = false;
  bool _hasPublicUsername = false;
  // Deferred-save originals (AyuGram queues all setting changes into one Save
  // pipeline; `validateXxx`/`saveXxx` skips RPCs whose value is unchanged).
  String _origDescription = '';
  bool _origForumEnabled = false;
  bool _origForumTabs = true;
  bool _origHistoryHidden = false;
  bool _origAutoTranslateDisabled = true;
  bool _origSignMessages = false;
  bool _origSignProfiles = false;
  String _origLinkedChatId = '';
  // Current allowed-reactions, so the Reactions box opens pre-filled.
  String _reactionsMode = 'none';
  List<String> _reactionsAllowed = const [];
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
  // Live counts shown on the right of the manage-section rows (the count labels
  // AyuGram renders via CreateButton/AddButtonWithCount, edit_peer_info_box.cpp).
  // _defaultBannedRights stays null until loaded so the Permissions row hides its
  // count rather than showing a wrong "all allowed" while the RPC is in flight.
  Map<String, dynamic>? _defaultBannedRights;
  int _inviteLinksCount = 0;

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

  // Server-driven minimum (appConfig telegram_antispam_group_size_min), loaded
  // from GetChatPermissionFlags; 100 is only the fallback default.
  int _antispamMinMembers = 100;

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
    if (_isBot) {
      _loadBotManageInfo();
    } else {
      _loadManageCounts();
    }
  }

  /// Loads the live counts shown on the Reactions / Permissions / Invite-Links
  /// manage rows. Reactions is already covered by GetChatPermissionFlags; this
  /// fetches the admin's own invite-link count (AyuGram requestMyLinks(peer)->count,
  /// edit_peer_info_box.cpp:1581) and the chat's default restrictions for the
  /// Permissions "allowed/total" count (RestrictionsCountValue, :1549).
  Future<void> _loadManageCounts() async {
    final engine = context.read<EngineService>();
    try {
      final links = await engine.getExportedChatInvites(
          widget.chat.accountId, widget.chat.chatId);
      if (mounted) setState(() => _inviteLinksCount = links.length);
    } catch (e) {
      Debug.log('admin_tools', 'getExportedChatInvites (count): $e');
    }
    try {
      final banned = await engine.getDefaultBannedRights(
          widget.chat.accountId, widget.chat.chatId);
      if (mounted) setState(() => _defaultBannedRights = banned);
    } catch (e) {
      Debug.log('admin_tools', 'getDefaultBannedRights (count): $e');
    }
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
    } catch (e) {
      Debug.log('admin_tools', 'final info = await engine.getBotManageInfo(: $e');
    }
    // Currency (TON ad-revenue) row gates on GetStarsRevenueStats; the rows
    // stay hidden until a non-zero balance is confirmed (AyuGram wraps them in
    // SlideWrap.toggle(!balance.isEmpty())).
    try {
      final stats = await engine.getStarsRevenueStats(
        widget.chat.accountId,
        widget.chat.chatId,
      );
      if (stats != null) {
        final current = stats['current_balance'] as int? ?? 0;
        final overall = stats['overall_revenue'] as int? ?? 0;
        hasCurrency = overall > 0 || current > 0;
      }
    } catch (e) {
      Debug.log('admin_tools', 'final stats = await engine.getStarsRevenueStats(: $e');
    }
    // Credits (Stars) row gates on the SEPARATE CreditsStatus (PaymentsGetStarsStatus
    // balance), not the currency revenue stats (edit_peer_info_box.cpp:1933).
    try {
      final credits = await engine.getChannelStarsTransactions(
        widget.chat.accountId,
        widget.chat.chatId,
        limit: 1,
      );
      final balance = (credits['balance'] as num?)?.toInt() ?? 0;
      hasCredits = balance > 0;
    } catch (e) {
      Debug.log('admin_tools', 'credits status: $e');
    }
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
          setState(() {
            _descCtrl.text = about;
            _origDescription = about;
          });
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
      } catch (e) {
        Debug.log('admin_tools', 'final profile = await engine.getUserProfile(: $e');
      }
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
          _origHistoryHidden = _historyHidden;
          _historyLoaded = true;
          _canEditPreHistoryHidden = flags['can_edit_pre_history_hidden'] as bool? ?? true;
          _signMessages = flags['signatures'] == true;
          _signProfiles = flags['signature_profiles'] == true;
          _origSignMessages = _signMessages;
          _origSignProfiles = _signProfiles;
          _signMessagesLoaded = true;
          _autoTranslateDisabled = flags['no_translations'] == true;
          _origAutoTranslateDisabled = _autoTranslateDisabled;
          _autoTranslateLoaded = true;
          _autoTranslateMinLevel = (flags['auto_translate_min_level'] as int?) ?? 0;
          _linkedChatId = (flags['linked_chat_id'] as String?) ?? '';
          _origLinkedChatId = _linkedChatId;
          _forumTabs = flags['forum_tabs'] as bool? ?? true;
          _origForumEnabled = _forumEnabled;
          _origForumTabs = _forumTabs;
          _hasLocation = flags['has_location'] == true;
          _reactionsMode = (flags['reactions_mode'] as String?) ?? 'none';
          _reactionsAllowed = ((flags['reactions_allowed'] as List?)?.cast<String>()) ?? const [];
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
          _antispamMinMembers = (flags['antispam_group_size_min'] as num?)?.toInt() ?? 100;
        });
        if (_linkedChatId.isNotEmpty) _resolveLinkedTitle(_linkedChatId);
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

  /// Resolves the linked discussion-group / channel's real title so the row
  /// shows its name reactively instead of a static "Linked"
  /// (edit_peer_info_box.cpp:1068).
  Future<void> _resolveLinkedTitle(String id) async {
    final engine = context.read<EngineService>();
    try {
      final info = await engine.getFullChatInfo(widget.chat.accountId, id);
      final title = info['title'] as String? ?? '';
      if (title.isNotEmpty && mounted) setState(() => _linkedChatTitle = title);
    } catch (_) {/* keep fallback label */}
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
              child: Builder(builder: (_) {
                final _lvKids = <Widget>[
                  _buildPhotoSection(accentColor, textColor, subTextColor),
                  _buildTitleField(textColor),
                  _buildDescriptionField(textColor, subTextColor),
                  Divider(height: 1, color: dividerColor),
                  const SizedBox(height: 6),
                  _buildSettingsSection(textColor, subTextColor, accentColor),
                  Divider(height: 1, color: dividerColor),
                  const SizedBox(height: 6),
                  _buildAdminControlsSection(textColor, subTextColor),
                  // NOTE: the aggressive anti-spam toggle is intentionally NOT
                  // here — AyuGram renders it as the "above" widget of the
                  // Admins participant-list box (edit_participants_box.cpp:1352),
                  // so it lives in _MemberListScreen's admins tab instead.
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
                ];
                return ListView.builder(
                  padding: EdgeInsets.zero,
                shrinkWrap: true,
                  itemCount: _lvKids.length,
                  itemBuilder: (_, _lvI) => _lvKids[_lvI],
                );
              }),
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
    // AyuGram uses channel->hasUsername(); a public peer has a username. The
    // engine surfaces this directly via GetChatPermissionFlags has_username,
    // so we no longer infer privacy from the -100 chatId prefix.
    final isPrivate = !_hasPublicUsername;
    // refreshHistoryVisibility also hides the row for location-based channels
    // (edit_peer_info_box.cpp:864).
    final showHistoryVis = !_isChannel
        && !_hasPublicUsername
        && !_forumEnabled
        && !_hasLocation
        && _linkedChatId.isEmpty
        && _canEditPreHistoryHidden;
    final topicsLocked = (!_forumEnabled && chat.memberCount < _forumMinMembers)
        || _linkedChatId.isNotEmpty;
    // canEditForum() = (isMegagroup && amCreator) for supergroups, or chat
    // creator for legacy basic groups (edit_peer_info_box.cpp:1443).
    final canEditForum = !_isChannel && !_isBot && _amCreator
        && (_isMegagroupFlag || !_isChannelOrSuper);

    return Column(
      children: [
        // fillPrivacyTypeButton is gated on channel->amCreator(), not merely
        // canEditInformation (edit_peer_info_box.cpp:1432).
        if (_amCreator)
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
          // Reactively show the linked peer's actual name; fall back to the
          // add/restore label when nothing is linked (edit_peer_info_box.cpp:1068).
          value: _linkedChatId.isNotEmpty
              ? (_linkedChatTitle.isNotEmpty ? _linkedChatTitle : 'Linked')
              : (_isChannel ? 'Add' : 'Add'),
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
          if (canEditForum)
            _EditRow(
              icon: Icons.topic_outlined,
              label: 'Topics',
              value: _forumEnabled ? 'On' : 'Off',
              textColor: textColor,
              subTextColor: subTextColor,
              // Locked state mirrors AyuGram setToggleLocked: greyed control,
              // tap still surfaces the reason (linked group / too few members).
              isToggle: topicsLocked,
              toggleValue: topicsLocked ? _forumEnabled : null,
              locked: topicsLocked,
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
              // Contextual about line: switches phrasing depending on whether
              // author profiles are also shown (edit_peer_info_box.cpp:1320).
              subtitle: _signMessages
                  ? (_signProfiles
                      ? 'Add names and links to the profiles of admins.'
                      : 'Add names of admins to their messages.')
                  : null,
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
        } catch (e) {
          Debug.log('admin_tools', 'groups = await engine.getDiscussionGroups(widget.chat.acc...: $e');
        }
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
                            onTap: () {
                              // Deferred: stage the choice; saveDiscussionLink
                              // applies it in the Save pipeline
                              // (edit_peer_info_box.cpp:2373).
                              Navigator.pop(ctx);
                              setState(() {
                                _linkedChatId = gId;
                                _linkedChatTitle = gTitle;
                              });
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
                  onPressed: () {
                    // Deferred unlink — committed on Save.
                    Navigator.pop(ctx);
                    setState(() {
                      _linkedChatId = '';
                      _linkedChatTitle = '';
                    });
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
    // The dialog edits a local copy; only Save commits it to the deferred
    // pipeline. Cancel with changes prompts a discard confirmation
    // (edit_peer_history_visibility_box.cpp:40).
    bool selectedHidden = _historyHidden;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> tryClose() async {
            if (selectedHidden == _historyHidden) {
              Navigator.pop(ctx);
              return;
            }
            final discard = await showDialog<bool>(
              context: ctx,
              builder: (c2) => AlertDialog(
                backgroundColor: bgColor,
                content: Text('Discard changes?', style: TextStyle(color: textColor)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('Back')),
                  TextButton(onPressed: () => Navigator.pop(c2, true), child: const Text('Discard')),
                ],
              ),
            );
            if (discard == true && ctx.mounted) Navigator.pop(ctx);
          }

          Widget radio(bool hidden, String title, String about) => InkWell(
                onTap: () => setLocal(() => selectedHidden = hidden),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Radio<bool>(
                      value: hidden,
                      groupValue: selectedHidden,
                      activeColor: accentColor,
                      onChanged: (v) => setLocal(() => selectedHidden = v!),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(title, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500)),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 2, bottom: 8),
                            child: Text(about, style: TextStyle(color: subTextColor, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );

          return AlertDialog(
            backgroundColor: bgColor,
            title: Text('Chat History for New Members',
                style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  radio(false, 'Visible', 'New members will see messages that were sent before they joined.'),
                  radio(true, 'Hidden', 'New members won\'t see more than 100 previous messages.'),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: tryClose, child: Text('Cancel', style: TextStyle(color: subTextColor))),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _setHistoryVisibility(selectedHidden);
                },
                child: Text('Save', style: TextStyle(color: accentColor)),
              ),
            ],
          );
        },
      ),
    );
  }

  // Deferred: stores the chosen value for the Save pipeline
  // (validateHistoryVisibility → saveHistoryVisibility), not an immediate RPC.
  void _setHistoryVisibility(bool hidden) {
    setState(() => _historyHidden = hidden);
  }

  Future<void> _toggleTopics() async {
    // AyuGram shows ToggleTopicsBox so the admin chooses Tabs vs List layout;
    // both `enabled` and `tabs` are then queued for the Save pipeline.
    await showToggleTopicsBox(
      context,
      enabled: _forumEnabled,
      tabs: _forumTabs,
      onSave: (enabled, tabs) {
        setState(() {
          _forumEnabled = enabled;
          _forumTabs = !enabled || tabs;
          // Enabling topics forces pre-history visible (toggle_topics_box flow).
          if (enabled) _historyHidden = false;
        });
      },
    );
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
    } catch (e) {
      Debug.log('admin_tools', 'boostData = await engine.getBoosts(widget.chat.accountId,...: $e');
    }
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

  // Deferred: AyuGram stores `_autotranslateSavedValue` and applies it via
  // saveAutotranslate in the Save pipeline (edit_peer_info_box.cpp:2684).
  void _toggleAutoTranslate() {
    final minLevel = _autoTranslateMinLevel > 0 ? _autoTranslateMinLevel : 3;
    final enabled = !_autoTranslateDisabled; // current on/off state
    final target = !enabled; // state we are toggling to
    // Enabling auto-translation requires the channel to have reached minLevel.
    if (target && _boostLevel < minLevel) {
      _showBoostRequiredDialog(_boostLevel, minLevel);
      return;
    }
    setState(() => _autoTranslateDisabled = !target);
  }

  // Deferred: AyuGram stores `_signaturesSavedValue`/`_signatureProfilesSavedValue`
  // and saves them together via saveSignatures() (edit_peer_info_box.cpp:2707).
  void _toggleSignMessages() {
    final newVal = !_signMessages;
    setState(() {
      _signMessages = newVal;
      if (!newVal) _signProfiles = false;
    });
  }

  void _toggleSignProfiles() {
    setState(() => _signProfiles = !_signProfiles);
  }

  Future<void> _showReactionsDialog(Color textColor, Color subTextColor) async {
    final engine = context.read<EngineService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final accentColor = PaletteProvider.of(context).windowBgActive;

    List<String> availableReactions = [];
    try {
      availableReactions = await engine.getAvailableReactions(widget.chat.accountId);
    } catch (e) {
      Debug.log('admin_tools', 'availableReactions = await engine.getAvailableReactions(w...: $e');
    }

    if (!mounted) return;

    // Pre-populate from the peer's current allowed-reactions instead of always
    // defaulting to "all" (edit_peer_info_box.cpp:1512).
    String mode = _reactionsMode.isNotEmpty ? _reactionsMode : 'all';
    final selectedEmojis = <String>{..._reactionsAllowed};
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
    } catch (e) {
      Debug.log('admin_tools', 'colors = await engine.getPeerColors(widget.chat.accountId): $e');
    }
    if (!mounted || colors.isEmpty) {
      if (mounted) showTelegramToast(context, 'Could not load colors');
      return;
    }

    Map<String, dynamic> fullInfo = {};
    try {
      fullInfo = await engine.getFullChatInfo(widget.chat.accountId, widget.chat.chatId);
    } catch (e) {
      Debug.log('admin_tools', 'fullInfo = await engine.getFullChatInfo(widget.chat.accou...: $e');
    }

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
    } catch (e) {
      Debug.log('admin_tools', 'emojiIds = await engine.getBackgroundEmojiList(widget.cha...: $e');
    }
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
    } catch (e) {
      Debug.log('admin_tools', 'final req = await engine.getColorLevelRequirements(widget...: $e');
    }

    try {
      // AyuGram persists the name color, background emoji and emoji status as
      // independent fields (edit_peer_color_box.cpp:Set). The name color and
      // background emoji ride one channels.updateColor RPC (which carries both,
      // with the color omitted when unset, colorId < 0), so it must fire whenever
      // EITHER changed — not only when a color is set. The emoji status is a
      // separate channels.updateEmojiStatus RPC.
      if (colorChanged || bgChanged) {
        await engine.updateChannelColor(widget.chat.accountId, widget.chat.chatId, colorId,
          backgroundEmojiId: bgEmojiId);
      }
      if (statusChanged) {
        await engine.updateChannelEmojiStatus(widget.chat.accountId, widget.chat.chatId, statusId);
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
        // Currency row navigates to the full ChannelEarn page (Info::ChannelEarn::Make),
        // not a one-shot AlertDialog (edit_peer_info_box.cpp:1866).
        if (_botHasCurrencyBalance)
          _EditRow(
            icon: Icons.monetization_on_outlined,
            label: 'Currency Balance',
            value: '',
            textColor: textColor,
            subTextColor: subTextColor,
            onTap: () => _openMonetization('Currency'),
          ),
        // Credits row navigates to the full BotEarn page (Info::BotEarn::Make).
        if (_botHasCreditsBalance)
          _EditRow(
            icon: Icons.stars_outlined,
            label: 'Credits Balance',
            value: '',
            textColor: textColor,
            subTextColor: subTextColor,
            onTap: () => _openMonetization('Credits'),
          ),
        // Affiliate (star-ref) setup navigates to the full Info::BotStarRef::Setup
        // page (commission slider + duration), gated by the appConfig
        // starref_program_allowed (edit_peer_info_box.cpp:1985).
        if (_botStarRefAllowed)
          _EditRow(
            icon: Icons.handshake_outlined,
            label: 'Affiliate Program',
            value: '',
            textColor: textColor,
            subTextColor: subTextColor,
            onTap: () => _openBotStarRefSetup(),
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
    } catch (e) {
      Debug.log('admin_tools', 'final fetched = await engine.getChatUsername(widget.chat....: $e');
    }
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

  void _openMonetization(String label) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _MonetizationScreen(
        accountId: widget.chat.accountId,
        chatId: widget.chat.chatId,
        title: '${widget.chat.title} · $label',
      ),
    ));
  }

  void _openBotStarRefSetup() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _BotStarRefSetupScreen(
        accountId: widget.chat.accountId,
        chatId: widget.chat.chatId,
        botName: widget.chat.title,
      ),
    ));
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
    } catch (e) {
      Debug.log('admin_tools', 'final fullInfo = await engine.getFullChatInfo(: $e');
    }
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
    } catch (e) {
      Debug.log('admin_tools', 'contacts = await engine.getContacts(widget.chat.accountId): $e');
    }
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

  // Reactions count label, mirroring AyuGram (edit_peer_info_box.cpp:1523-1534):
  // "All" when reactions aren't restricted to a specific set, otherwise the
  // allowed-count, else "1" for paid-only, else "Off".
  String _reactionsCountLabel() {
    if (_reactionsMode == 'all') return 'All';
    final some = _reactionsAllowed.length;
    if (some > 0) return '$some';
    if (_paidReactionsEnabled) return '1';
    return 'Off';
  }

  // Permissions "allowed/total" count, mirroring RestrictionsCountValue +
  // ListOfRestrictions().size() (edit_peer_info_box.cpp:1549-1556). Returns the
  // number of NOT-restricted rights over the total. Empty until loaded, and only
  // meaningful for groups (a broadcast channel has no member restrictions).
  String _permissionsCountLabel() {
    if (_isBroadcastFlag) return '';
    final banned = _defaultBannedRights;
    if (banned == null) return '';
    // The flattened restriction list (data_chat_participant_status RestrictionLabels):
    // 14 entries, +1 (CreateTopics→manage_topics) for forums.
    const baseKeys = [
      'send_plain', 'send_photos', 'send_videos', 'send_roundvideos',
      'send_audios', 'send_voices', 'send_docs', 'send_stickers',
      'embed_links', 'send_polls', 'invite_users', 'pin_messages',
      'edit_rank', 'change_info',
    ];
    final keys = [...baseKeys, if (widget.chat.isForum) 'manage_topics'];
    final restricted = keys.where((k) => banned[k] == true).length;
    return '${keys.length - restricted}/${keys.length}';
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
          value: _reactionsCountLabel(),
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => _showReactionsDialog(textColor, subTextColor),
        ),
        _EditRow(
          icon: Icons.security,
          label: 'Permissions',
          value: _permissionsCountLabel(),
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
            // Public channels & linked-discussion groups lock ChangeInfo|PinMessages.
            isPublic: _hasPublicUsername,
            hasDiscussionLink: _linkedChatId.isNotEmpty,
          ),
        ),
        _EditRow(
          icon: Icons.link,
          label: 'Invite Links',
          // Admin's own link count (incl. the primary link); empty when none,
          // matching AyuGram ToPositiveNumberString (edit_peer_info_box.cpp:1581-1593).
          value: _inviteLinksCount > 0 ? '$_inviteLinksCount' : '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => _showInviteLink(),
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
        // AyuGram order: fillPendingRequestsButton runs BETWEEN Members and
        // Removed Users (edit_peer_info_box.cpp:1635).
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
        // Affiliate Program (star-ref JOIN) is ordered LAST, after Recent
        // Actions (edit_peer_info_box.cpp:1663). Statistics/Boosts/Monetization
        // are NOT in fillManageSection — they live as Info-panel section pages.
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
      // saveDescription skips the RPC when unchanged, avoiding
      // CHAT_ABOUT_NOT_MODIFIED (edit_peer_info_box.cpp:2508).
      if (newDesc != _origDescription) {
        await engine.editChatDescription(
          widget.chat.accountId,
          widget.chat.chatId,
          newDesc,
        );
      }
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
      // ── Deferred setting changes, queued from their dialogs (AyuGram's
      // validateXxx → saveXxx pipeline). Each skips its RPC when unchanged. ──
      if (_linkedChatId != _origLinkedChatId) {
        // saveDiscussionLink: set or clear the broadcast↔group link.
        await engine.setDiscussionGroup(
          widget.chat.accountId,
          _isChannel ? widget.chat.chatId : (_linkedChatId.isEmpty ? '' : _linkedChatId),
          _isChannel ? _linkedChatId : widget.chat.chatId,
        );
      }
      if (_forumEnabled != _origForumEnabled || _forumTabs != _origForumTabs) {
        await engine.toggleForumTabs(
          widget.chat.accountId,
          widget.chat.chatId,
          _forumEnabled,
          _forumTabs,
        );
      }
      if (_historyHidden != _origHistoryHidden) {
        await engine.togglePreHistoryHidden(
          widget.chat.accountId,
          widget.chat.chatId,
          _historyHidden,
        );
      }
      if (_autoTranslateDisabled != _origAutoTranslateDisabled) {
        // channels.toggleAutotranslation takes the ENABLED state.
        await engine.toggleChannelAutoTranslation(
          widget.chat.accountId,
          widget.chat.chatId,
          !_autoTranslateDisabled,
        );
      }
      if (_signMessages != _origSignMessages || _signProfiles != _origSignProfiles) {
        await engine.toggleSignatures(
          widget.chat.accountId,
          widget.chat.chatId,
          _signMessages,
          profilesEnabled: _signMessages ? _signProfiles : false,
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
  // For public channels (or channels with a linked discussion group) AyuGram
  // force-disables ChangeInfo|PinMessages with a tooltip
  // (edit_peer_permissions_box.cpp:1132).
  bool isPublic = false,
  bool hasDiscussionLink = false,
}) {
  return showDialog(
    context: context,
    builder: (ctx) => _EditPeerPermissionsBox(
      accountId: accountId,
      isPublic: isPublic,
      hasDiscussionLink: hasDiscussionLink,
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
  final bool isPublic;
  final bool hasDiscussionLink;

  const _EditPeerPermissionsBox({
    required this.accountId,
    required this.chatId,
    required this.isChannel,
    required this.isForum,
    required this.memberCount,
    required this.paidMessagesPossible,
    this.isPublic = false,
    this.hasDiscussionLink = false,
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
  int _chargeMax = 10000; // appConfig stars_paid_message_amount_max
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
    // Public channels / channels with a linked discussion group force-disable
    // ChangeInfo|PinMessages (they're always admin-only there); AyuGram renders
    // them locked with a tooltip (edit_peer_permissions_box.cpp:1132).
    final lockInfoPin = widget.isPublic || widget.hasDiscussionLink;
    _otherFlags = [
      _PermFlag(key: 'invite_users', label: 'Add members'),
      if (widget.isForum) _PermFlag(key: 'manage_topics', label: 'Create topics'),
      _PermFlag(key: 'pin_messages', label: 'Pin messages', locked: lockInfoPin),
      // EditRank is rendered but always locked (NestedRestrictionLabelsList →
      // disabledMessages); lng_rights_group_edit_rank = "Edit own tags".
      _PermFlag(key: 'edit_rank', label: 'Edit own tags', locked: true),
      _PermFlag(key: 'change_info', label: 'Change group info', locked: lockInfoPin),
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
      if (widget.paidMessagesPossible) {
        try {
          _chargeMax = await engine.getStarsPaidPostAmountMax(widget.accountId);
          if (_chargeMax <= 0) _chargeMax = 10000;
        } catch (_) {}
      }
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
                child: Builder(builder: (_) {
                  final _lvKids = <Widget>[
                    const SizedBox(height: 8),
                    _buildSectionHeader('What can members of this group do?', headerColor),
                    const SizedBox(height: 4),
                    _buildPermToggle(_sendPlain, accentColor, attentionColor, textColor),
                    _buildMediaSection(accentColor, attentionColor, textColor, subTextColor),
                    for (final f in _otherFlags)
                      _buildPermToggle(f, accentColor, attentionColor, textColor),
                    // AyuGram section order is Charge-Stars → Boosts → Slow Mode
                    // (edit_peer_permissions_box.cpp:1182-1235).
                    if (widget.paidMessagesPossible) ...[
                      Divider(height: 1, color: dividerColor),
                      const SizedBox(height: 12),
                      _buildSectionHeader('Charge Stars', headerColor),
                      const SizedBox(height: 4),
                      _buildChargeStarsSection(accentColor, textColor, subTextColor),
                    ],
                    // Boosts-to-unrestrict is only shown when there are send
                    // restrictions or slow mode (AddBoostsUnrestrictWrapped gated
                    // on hasSendRestrictions; edit_peer_permissions_box.cpp:1226-1229).
                    if (_boostsSectionVisible) ...[
                      Divider(height: 1, color: dividerColor),
                      const SizedBox(height: 12),
                      _buildBoostsSection(accentColor, textColor, subTextColor),
                    ],
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
                    _buildAddExceptionButton(accentColor, textColor),
                    // AddBannedButtons adds BOTH an Exceptions button and a
                    // Removed-users (kicked) button for channels
                    // (edit_peer_permissions_box.cpp:1092).
                    if (widget.isChannel)
                      _buildRemovedUsersButton(accentColor, textColor),
                    const SizedBox(height: 12),
                  ];
                  return ListView.builder(
                    padding: EdgeInsets.zero,
                  shrinkWrap: true,
                    itemCount: _lvKids.length,
                    itemBuilder: (_, _lvI) => _lvKids[_lvI],
                  );
                }),
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
          final why = (flag.key == 'change_info' || flag.key == 'pin_messages')
                  && (widget.isPublic || widget.hasDiscussionLink)
              ? (widget.isPublic
                  ? 'This permission is always restricted in public groups/channels.'
                  : 'This permission is always restricted when a discussion group is linked.')
              : 'You cannot change this permission.';
          showTelegramToast(context, why);
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
        if (_chargeStars > 0) ...[
          // Non-linear SetupChargeSlider: 1–100 step 1, 100–1000 step 10, 1000+
          // step 100, minimum 1 while enabled (allowZero=false)
          // (edit_privacy_box.cpp:1219-1220).
          Builder(builder: (_) {
            final values = _chargeStarValues(_chargeMax);
            int idx = values.indexOf(_chargeStars);
            if (idx < 0) {
              // Snap to the nearest preset for an off-grid existing value.
              idx = 0;
              for (int i = 0; i < values.length; i++) {
                if (values[i] <= _chargeStars) idx = i;
              }
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.star, size: 18, color: const Color(0xFFFFB800)),
                      const SizedBox(width: 6),
                      Text('$_chargeStars',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textColor)),
                    ],
                  ),
                ),
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: accentColor,
                    inactiveTrackColor: accentColor.withValues(alpha: 0.3),
                    thumbColor: accentColor,
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: idx.toDouble().clamp(0, (values.length - 1).toDouble()),
                    min: 0,
                    max: (values.length - 1).toDouble(),
                    onChanged: (v) => setState(() {
                      _chargeStars = values[v.round().clamp(0, values.length - 1)];
                      _chargeStarsCtrl.text = '$_chargeStars';
                    }),
                  ),
                ),
              ],
            );
          }),
        ],
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

  Widget _buildRemovedUsersButton(Color accentColor, Color textColor) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        showMemberListScreen(
          context,
          accountId: widget.accountId,
          chatId: widget.chatId,
          isChannel: widget.isChannel,
          isForum: widget.isForum,
          initialTab: _MemberTab.kicked,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.person_remove_outlined, size: 24, color: accentColor),
            const SizedBox(width: 16),
            Text(
              'Removed Users',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accentColor),
            ),
          ],
        ),
      ),
    );
  }

  // Non-linear charge-stars value list (SetupChargeSlider, edit_privacy_box.cpp:1219):
  // 1–100 step 1, 100–1000 step 10, 1000+ step 100. Used by the slider.
  static List<int> _chargeStarValues(int maxStars) {
    final values = <int>[];
    for (int v = 1; v <= 100 && v <= maxStars; v++) {
      values.add(v);
    }
    for (int v = 110; v <= 1000 && v <= maxStars; v += 10) {
      values.add(v);
    }
    for (int v = 1100; v <= maxStars; v += 100) {
      values.add(v);
    }
    if (values.isEmpty) values.add(1);
    return values;
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
  // Optional secondary line under the label (e.g. the Sign-Messages "about"
  // description that switches between messages/profiles context).
  final String? subtitle;
  // AyuGram's setToggleLocked: the toggle renders greyed/disabled but the row
  // is still tappable (it surfaces the "why" tooltip).
  final bool locked;

  const _EditRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.textColor,
    required this.subTextColor,
    this.isToggle = false,
    this.toggleValue,
    required this.onTap,
    this.subtitle,
    this.locked = false,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: TextStyle(fontSize: 12, color: subTextColor),
                      ),
                    ),
                ],
              ),
            ),
            if (isToggle)
              IgnorePointer(
                ignoring: locked,
                child: Opacity(
                  opacity: locked ? 0.45 : 1.0,
                  child: Switch(value: toggleValue ?? false, onChanged: (_) => onTap()),
                ),
              )
            else if (value.isNotEmpty)
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: subTextColor),
                ),
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

/// Full-page bot affiliate-program setup, mirroring AyuGram
/// `Info::BotStarRef::Setup::Make(user)` (info_bot_starref_setup_widget.cpp):
/// a commission slider (min→max from appConfig) plus a duration chooser
/// ({1,3,6,12,24,36,forever} months). Replaces the previous AlertDialog.
class _BotStarRefSetupScreen extends StatefulWidget {
  final String accountId;
  final String chatId;
  final String botName;

  const _BotStarRefSetupScreen({
    required this.accountId,
    required this.chatId,
    required this.botName,
  });

  @override
  State<_BotStarRefSetupScreen> createState() => _BotStarRefSetupScreenState();
}

class _BotStarRefSetupScreenState extends State<_BotStarRefSetupScreen> {
  // appConfig bounds (starref_min/max_commission_permille); 1%–90% defaults.
  int _commissionMin = 10; // permille
  int _commissionMax = 900; // permille
  int _commissionPermille = 200; // current selection (default 20%)
  // Durations in months; 999 == forever (info_bot_starref_setup_widget.cpp:681).
  static const _durations = [1, 3, 6, 12, 24, 36, 999];
  int _durationMonths = 12;
  bool _hasProgram = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final engine = context.read<EngineService>();
    try {
      final info = await engine.getBotManageInfo(widget.accountId, widget.chatId);
      final cmin = (info['starref_commission_min'] as num?)?.toInt() ?? 10;
      final cmax = (info['starref_commission_max'] as num?)?.toInt() ?? 900;
      final cur = (info['starref_commission'] as num?)?.toInt() ?? 0;
      Map<String, dynamic> program = {};
      try {
        final full = await engine.getFullChatInfo(widget.accountId, widget.chatId);
        program = full['star_ref_program'] as Map<String, dynamic>? ?? {};
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _commissionMin = cmin > 0 ? cmin : 10;
        _commissionMax = cmax > _commissionMin ? cmax : 900;
        _hasProgram = program.isNotEmpty || cur > 0;
        _commissionPermille = (program['commission_permille'] as num?)?.toInt() ??
            (cur > 0 ? cur : 200);
        _commissionPermille = _commissionPermille.clamp(_commissionMin, _commissionMax);
        final dm = (program['duration_months'] as num?)?.toInt() ?? 12;
        _durationMonths = dm == 0 ? 999 : dm;
        if (!_durations.contains(_durationMonths)) _durationMonths = 12;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _commissionLabel(int permille) {
    final v = permille / 10.0;
    return '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString()}%';
  }

  String _durationLabel(int m) => m >= 999
      ? 'Forever'
      : (m % 12 == 0 ? '${m ~/ 12} year${m == 12 ? '' : 's'}' : '$m months');

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final engine = context.read<EngineService>();
    try {
      await engine.setStarRefProgram(
        widget.accountId,
        widget.chatId,
        commissionPermille: _commissionPermille,
        durationMonths: _durationMonths >= 999 ? 0 : _durationMonths,
      );
      if (mounted) {
        showTelegramToast(context, 'Affiliate program updated');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showTelegramToast(context, 'Failed: $e');
      }
    }
  }

  Future<void> _end() async {
    final engine = context.read<EngineService>();
    try {
      // commissionPermille==0 ends/removes the program (bots.updateStarRefProgram).
      await engine.setStarRefProgram(widget.accountId, widget.chatId,
          commissionPermille: 0, durationMonths: 0);
      if (mounted) {
        showTelegramToast(context, 'Affiliate program ended');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showTelegramToast(context, 'Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = PaletteProvider.of(context);
    final accent = palette.windowBgActive;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subText = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    final divisions = ((_commissionMax - _commissionMin) ~/ 10).clamp(1, 1000);

    return Scaffold(
      appBar: AppBar(title: const Text('Affiliate Program', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Reward affiliates who bring users to ${widget.botName}.',
                    style: TextStyle(color: subText, fontSize: 14)),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_commissionLabel(_commissionMin), style: TextStyle(color: subText, fontSize: 12)),
                    Text(_commissionLabel(_commissionPermille),
                        style: TextStyle(color: accent, fontSize: 15, fontWeight: FontWeight.w600)),
                    Text(_commissionLabel(_commissionMax), style: TextStyle(color: subText, fontSize: 12)),
                  ],
                ),
                Slider(
                  value: _commissionPermille.toDouble().clamp(_commissionMin.toDouble(), _commissionMax.toDouble()),
                  min: _commissionMin.toDouble(),
                  max: _commissionMax.toDouble(),
                  divisions: divisions,
                  activeColor: accent,
                  label: _commissionLabel(_commissionPermille),
                  onChanged: (v) => setState(() => _commissionPermille = (v / 10).round() * 10),
                ),
                const SizedBox(height: 8),
                Text('DURATION', style: TextStyle(color: subText, fontSize: 12, fontWeight: FontWeight.w600)),
                ..._durations.map((m) => RadioListTile<int>(
                      value: m,
                      groupValue: _durationMonths,
                      activeColor: accent,
                      dense: true,
                      title: Text(_durationLabel(m)),
                      onChanged: (v) => setState(() => _durationMonths = v!),
                    )),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: accent),
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving…' : (_hasProgram ? 'Update Program' : 'Start Program')),
                  ),
                ),
                if (_hasProgram)
                  TextButton(
                    onPressed: _end,
                    child: Text('End Affiliate Program', style: TextStyle(color: palette.attentionButtonFg)),
                  ),
              ],
            ),
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
  // Attribution footer ("Restricted by X on DATE", edit_participant_box.cpp:816).
  String _bannedByName = '';
  int _bannedDate = 0;
  // Flags banned by the chat's defaultRestrictions render locked-ON ("Forbidden
  // for all members") — you can't grant a member a permission denied to everyone
  // (edit_participant_box.cpp:746).
  final Set<String> _defaultBannedKeys = {};
  // Whether the editor can promote this member (gates the "Promote to admin"
  // action button, edit_participant_box.cpp:844).
  bool _canAddAdmins = false;

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
      String bannedByName = '';
      int bannedDate = 0;
      // Always load the chat's default restrictions so flags forbidden for
      // everyone can be locked (edit_participant_box.cpp:746).
      Map<String, dynamic> defaults = {};
      try {
        defaults = await engine.getDefaultBannedRights(widget.accountId, widget.chatId);
      } catch (_) {}
      // The editor's promote capability gates the "Promote to admin" button.
      try {
        final flags = await engine.getChatPermissionFlags(widget.accountId, widget.chatId);
        _canAddAdmins = flags['can_add_admins'] == true || flags['am_creator'] == true;
      } catch (_) {}
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
            rights = defaults;
          }
          bannedUntil = (info['banned_until'] as num?)?.toInt() ?? 0;
          bannedByName = info['banned_by_name'] as String? ?? '';
          bannedDate = (info['banned_date'] as num?)?.toInt() ?? 0;
        } catch (_) {
          rights = defaults;
        }
      } else {
        rights = defaults;
      }
      if (!mounted) return;
      setState(() {
        _bannedByName = bannedByName;
        _bannedDate = bannedDate;
        _defaultBannedKeys
          ..clear()
          ..addAll([for (final f in _allFlags) if (defaults[f.key] == true) f.key]);
        for (final f in _allFlags) {
          // A flag banned for everyone is force-banned & locked.
          f.banned = rights[f.key] == true || _defaultBannedKeys.contains(f.key);
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
    if (flag.locked || _defaultBannedKeys.contains(flag.key)) return;
    setState(() {
      flag.banned = !flag.banned;
      _applyDependencies();
    });
  }

  // Full ApplyDependencies fixpoint (edit_peer_permissions_box.cpp:212-264).
  // Pair (restriction, dependency): banning the dependency bans the restriction;
  // allowing the restriction allows the dependency. Iterated to a fixpoint so a
  // cascade settles (e.g. ban send_plain → ban embed_links).
  void _applyDependencies() {
    // (restriction, dependency) pairs for the collapsed flag set. The sticker
    // sub-group is one flag here; embed_links depends on send_plain (SendOther).
    const pairs = [
      ['embed_links', 'send_plain'],
    ];
    _PermFlag? byKey(String k) {
      for (final f in _allFlags) {
        if (f.key == k) return f;
      }
      return null;
    }
    for (var i = 0; i < _allFlags.length; i++) {
      var changed = false;
      for (final p in pairs) {
        final restriction = byKey(p[0]);
        final dependency = byKey(p[1]);
        if (restriction == null || dependency == null) continue;
        // dependency banned ⇒ restriction banned
        if (dependency.banned && !restriction.banned && !restriction.locked) {
          restriction.banned = true;
          changed = true;
        }
        // restriction allowed ⇒ dependency allowed
        if (!restriction.banned && dependency.banned &&
            !dependency.locked && !_defaultBannedKeys.contains(dependency.key)) {
          dependency.banned = false;
          changed = true;
        }
      }
      if (!changed) break;
    }
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
      // Unified date+time box (AyuGram ChooseDateTimeBox, edit_participant_box.cpp:980):
      // a single dismiss cancels both, and the result is clamped to [now, now+366d].
      final result = await showChooseDateTimeBox(
        context,
        initialDate: initial,
        title: 'Restrict until',
        submitText: 'Restrict',
        showRepeat: false,
      );
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _duration = previousDuration;
          _customDate = previousCustom;
        });
        return;
      }
      var chosen = result.dateTime;
      if (!chosen.isAfter(now)) chosen = now.add(const Duration(minutes: 1));
      if (chosen.isAfter(maxDate)) chosen = maxDate;
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
                child: Builder(builder: (_) {
                  final _lvKids = <Widget>[
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
                    _buildAttributionFooter(subTextColor),
                    Divider(height: 1, color: dividerColor),
                    const SizedBox(height: 4),
                    _buildRestrictActions(accentColor, attentionColor, textColor),
                    const SizedBox(height: 12),
                  ];
                  return ListView.builder(
                    padding: EdgeInsets.zero,
                  shrinkWrap: true,
                    itemCount: _lvKids.length,
                    itemBuilder: (_, _lvI) => _lvKids[_lvI],
                  );
                }),
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
    // Forbidden for all members (defaultRestrictions) — locked & forced banned.
    final defaultLocked = _defaultBannedKeys.contains(flag.key);
    final isLocked = flag.locked || dependencyLocked || defaultLocked;

    return InkWell(
      onTap: () {
        if (defaultLocked) {
          showTelegramToast(context, 'This permission is forbidden for all members.');
          return;
        }
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(flag.label, style: TextStyle(fontSize: 14, color: textColor)),
                  if (defaultLocked)
                    Text('Forbidden for all members',
                        style: TextStyle(fontSize: 11, color: attentionColor)),
                ],
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
    // When a non-standard prior expiry exists, AyuGram's createUntilVariants
    // inserts that exact date as its own selectable radio so it isn't lost
    // (edit_participant_box.cpp:1029). We surface it as the "Custom" radio's
    // label so picking it keeps the original expiry.
    final hasCustomDate = _customDate != null;
    final customLabel = hasCustomDate
        ? 'Until ${_customDate!.year}-${_customDate!.month.toString().padLeft(2, '0')}-${_customDate!.day.toString().padLeft(2, '0')} '
            '${_customDate!.hour.toString().padLeft(2, '0')}:${_customDate!.minute.toString().padLeft(2, '0')}'
        : 'Custom...';
    return Column(
      children: [
        _buildDurationRadio(_BanDuration.forever, 'Ban forever', accentColor, textColor),
        _buildDurationRadio(_BanDuration.oneDay, 'Ban for 1 day', accentColor, textColor),
        _buildDurationRadio(_BanDuration.oneWeek, 'Ban for 1 week', accentColor, textColor),
        _buildDurationRadio(_BanDuration.custom, customLabel, accentColor, textColor),
        // A small "change date" affordance when an existing expiry is selected.
        if (_duration == _BanDuration.custom && hasCustomDate)
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 0, 22, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
                onPressed: _pickCustomDate,
                child: Text('Change date…', style: TextStyle(fontSize: 13, color: accentColor)),
              ),
            ),
          ),
      ],
    );
  }

  // "Restricted/Banned by X on DATE" attribution footer, shown when the ban
  // metadata is present (edit_participant_box.cpp:816).
  Widget _buildAttributionFooter(Color subTextColor) {
    if (_bannedDate <= 0 && _bannedByName.isEmpty) return const SizedBox.shrink();
    final d = DateTime.fromMillisecondsSinceEpoch(_bannedDate * 1000);
    final dateStr = _bannedDate > 0
        ? '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'
        : '';
    final verb = widget.member.role == 'banned' ? 'Banned' : 'Restricted';
    final by = _bannedByName.isNotEmpty ? ' by $_bannedByName' : '';
    final on = dateStr.isNotEmpty ? ' on $dateStr' : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
      child: Text('$verb$by$on', style: TextStyle(fontSize: 12, color: subTextColor)),
    );
  }

  // "Promote to admin" + "Remove from group" actions AyuGram appends at the
  // bottom of EditRestrictedBox (edit_participant_box.cpp:844).
  Widget _buildRestrictActions(Color accentColor, Color attentionColor, Color textColor) {
    return Column(
      children: [
        if (_canAddAdmins)
          InkWell(
            onTap: _promoteToAdmin,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
              child: Row(children: [
                Icon(Icons.admin_panel_settings_outlined, size: 22, color: accentColor),
                const SizedBox(width: 16),
                Text('Promote to admin',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accentColor)),
              ]),
            ),
          ),
        InkWell(
          onTap: _removeFromGroup,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
            child: Row(children: [
              Icon(Icons.block, size: 22, color: attentionColor),
              const SizedBox(width: 16),
              Text('Remove from group',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: attentionColor)),
            ]),
          ),
        ),
      ],
    );
  }

  void _promoteToAdmin() {
    Navigator.pop(context);
    showEditAdminBox(
      context,
      accountId: widget.accountId,
      chatId: widget.chatId,
      member: widget.member,
      // Restricting is a megagroup-only operation (isMegagroup && !isGigagroup),
      // so the promote target is always a supergroup, never a broadcast channel.
      isChannel: false,
      isForum: widget.isForum,
    );
  }

  Future<void> _removeFromGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from group'),
        content: Text('Remove ${widget.member.label} from the group?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final engine = context.read<EngineService>();
      await engine.banMember(widget.accountId, widget.chatId, widget.member.userId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showTelegramToast(context, 'Failed: $e');
    }
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

/// An expandable group of admin-right toggles ("Manage messages" / "Manage
/// stories") with a parent master toggle and a "checked/total" count, mirroring
/// AyuGram's nested SlideWrap + AddInnerToggle (edit_peer_permissions_box.cpp:
/// 366-548, 724-763). Collapsed initially; the header row expands/collapses the
/// children, and the master toggle on the right flips every child at once.
class _NestedRightsGroup extends StatefulWidget {
  final String label;
  final List<_AdminFlag> flags;
  final Color accentColor;
  final Color textColor;
  final VoidCallback onChanged;

  const _NestedRightsGroup({
    required this.label,
    required this.flags,
    required this.accentColor,
    required this.textColor,
    required this.onChanged,
  });

  @override
  State<_NestedRightsGroup> createState() => _NestedRightsGroupState();
}

class _NestedRightsGroupState extends State<_NestedRightsGroup> {
  // AyuGram hides the wrap on build (raw->hide(anim::type::instant), :745).
  bool _expanded = false;

  int get _checkedCount => widget.flags.where((f) => f.enabled).length;
  // Master toggle reflects "any child checked" (AyuGram setChecked(count > 0), :453).
  bool get _anyChecked => _checkedCount > 0;

  void _toggleAll() {
    // AyuGram toggleButton: checked = !checkView->checked(); set all children (:540).
    final next = !_anyChecked;
    setState(() {
      for (final f in widget.flags) {
        f.enabled = next;
      }
    });
    widget.onChanged();
  }

  void _toggleChild(_AdminFlag flag, bool value) {
    setState(() => flag.enabled = value);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;
    final text = widget.textColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Tapping the label area expands/collapses (AyuGram button->clicks, :530).
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: widget.label,
                              style: TextStyle(fontSize: 14, color: text),
                            ),
                            // Bold "checked/total" count, AyuGram tr::bold (:467).
                            TextSpan(
                              text: '  $_checkedCount/${widget.flags.length}',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600, color: text),
                            ),
                          ]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Arrow rotates 180° when expanded (AyuGram :490 / :511-519).
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOutCubic,
                        child: Icon(Icons.keyboard_arrow_down,
                            size: 18, color: text.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Vertical separator + master toggle (AyuGram's rightsButtonToggleWidth
            // area with a separator line, :413-434).
            Container(width: 1, height: 22, color: text.withValues(alpha: 0.12)),
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 16),
              child: SizedBox(
                height: 24,
                child: Switch(
                  value: _anyChecked,
                  onChanged: (_) => _toggleAll(),
                  activeColor: accent,
                ),
              ),
            ),
          ],
        ),
        // SlideWrap equivalent: children shown only when expanded.
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Column(
                  children: [
                    for (final flag in widget.flags)
                      InkWell(
                        onTap: () => _toggleChild(flag, !flag.enabled),
                        child: Padding(
                          // Children indented under the group header.
                          padding: const EdgeInsets.only(
                              left: 38, top: 8, right: 22, bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(flag.label,
                                    style: TextStyle(fontSize: 14, color: text)),
                              ),
                              const SizedBox(width: 20),
                              SizedBox(
                                height: 24,
                                child: Switch(
                                  value: flag.enabled,
                                  onChanged: (v) => _toggleChild(flag, v),
                                  activeColor: accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
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

  // The "Add as Admin" checkbox is shown ONLY when adding a non-existing bot to
  // a non-broadcast chat (`_addingBot && !existing && !isBroadcast`,
  // edit_participant_box.cpp:361). In every other case the box IS the admin
  // editor, so the member is always saved as an admin.
  bool get _addingBot => widget.member.isBot;
  bool get _existingMember =>
      widget.member.role == 'admin' ||
      widget.member.role == 'creator' ||
      widget.member.role == 'owner';
  bool get _showAddAsAdminCheckbox => _addingBot && !_existingMember && !_isBroadcast;
  // The chat creator can never be dismissed (edit_participant_box.cpp:554).
  bool get _isTargetCreator =>
      widget.member.role == 'creator' || widget.member.role == 'owner';

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
    } catch (e) {
      Debug.log('admin_tools', 'final engine = context.read<EngineService>(): $e');
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
    } catch (e) {
      Debug.log('admin_tools', 'final engine = context.read<EngineService>(): $e');
    }
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
      if (_showAddAsAdminCheckbox && !_addAsAdmin) {
        // Unchecked "Add as Admin" while adding a bot ⇒ AddBotToGroup (a plain
        // bot-add, NOT a demotion) — edit_participant_box.cpp:605.
        await engine.addMembers(widget.accountId, widget.chatId, [widget.member.userId]);
      } else {
        final rights = <String, bool>{};
        for (final f in _allFlags) {
          rights[f.key] = f.enabled;
        }
        // AyuGram always OR's ChatAdminRight::Other into the saved bitmask
        // (edit_participant_box.cpp:590); the backend forces it too.
        rights['other'] = true;
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
    // Pre-flight EditChatCreator probe with an empty password to route to the
    // right box BEFORE asking for the password (channel_ownership_transfer.cpp:48).
    String status;
    try {
      status = await engine.transferOwnershipPreflight(
        widget.accountId, widget.chatId, widget.member.userId);
    } catch (e) {
      if (mounted) showTelegramToast(context, _transferErrorMessage(e.toString()));
      return;
    }
    if (!mounted) return;
    switch (status) {
      case 'no_password':
        _showTransferSecurityCheck(later: false);
        return;
      case 'password_too_fresh':
      case 'session_too_fresh':
        // TransferPasswordError "Later" case (passcode_box.cpp:82).
        _showTransferSecurityCheck(later: true, sessionFresh: status == 'session_too_fresh');
        return;
      case 'need_password':
      case 'ok':
        break;
      default:
        showTelegramToast(context, _transferErrorMessage(status));
        return;
    }
    // After the pre-flight passes, AyuGram shows MakeConfirmBox
    // (lng_rights_transfer_about/_sure) THEN requestPassword()
    // (channel_ownership_transfer.cpp:60).
    final label = _isBroadcast ? 'channel' : 'group';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transfer Ownership'),
        content: Text(
          'This will transfer the full owner rights for this $label to '
          '${widget.member.label}. The new owner will be free to remove any of '
          'your admin privileges or even ban you.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Change Owner')),
        ],
      ),
    );
    if (confirmed == true && mounted) _showTransferPasswordDialog();
  }

  // PrePasswordErrorBox / TransferPasswordError NoPassword case
  // (passcode_box.cpp:65-99,1466): the editor has no 2FA password, so ownership
  // cannot be transferred until Two-Step Verification is enabled.
  // [later]=false → NoPassword case (2FA never enabled). [later]=true →
  // TransferPasswordError "Later" case: 2FA/session is too fresh, distinct
  // content + buttons (passcode_box.cpp:82).
  void _showTransferSecurityCheck({bool later = false, bool sessionFresh = false}) {
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
          later ? 'Please come back later' : 'Security check',
          style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        content: later
            ? Text(
                sessionFresh
                    ? 'You have logged in on this device too recently. Please try transferring ownership later.'
                    : 'You have enabled Two-Step Verification too recently. Please try transferring ownership in a few days.',
                style: TextStyle(color: subTextColor, fontSize: 14),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(about, style: TextStyle(color: subTextColor, fontSize: 14)),
                  const SizedBox(height: 12),
                  Text('• Enabled Two-Step Verification more than 7 days ago.',
                      style: TextStyle(color: subTextColor, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text('• Logged in on this device more than 24 hours ago.',
                      style: TextStyle(color: subTextColor, fontSize: 14)),
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
              child: Builder(builder: (_) {
                final _lvKids = <Widget>[
                  _buildCover(textColor, subTextColor, accentColor),
                  Divider(height: 1, color: dividerColor),
                  const SizedBox(height: 8),
                  if (_showAddAsAdminCheckbox)
                    _buildAddAsAdminCheckbox(accentColor, textColor),
                  SizeTransition(
                    // Rights are always shown unless the add-bot checkbox is
                    // present and unchecked.
                    sizeFactor: _showAddAsAdminCheckbox
                        ? _collapseAnim
                        : const AlwaysStoppedAnimation(1.0),
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
                        // §1 (first): flat — ChangeInfo (channel) / core group rights.
                        _buildRightsSection(
                          null,
                          _section1,
                          accentColor,
                          textColor,
                        ),
                        Divider(height: 1, indent: 22, endIndent: 22, color: dividerColor),
                        // §2: nested. Channel → "Manage messages" (Post/Edit/Delete
                        // Messages); group → "Manage stories" (NestedAdminRightLabels).
                        _buildRightsSection(
                          widget.isChannel ? 'Manage messages' : 'Manage stories',
                          _section2,
                          accentColor,
                          textColor,
                        ),
                        Divider(height: 1, indent: 22, endIndent: 22, color: dividerColor),
                        // §3: channel → nested "Manage stories"; group → flat (second).
                        _buildRightsSection(
                          widget.isChannel ? 'Manage stories' : null,
                          _section3,
                          accentColor,
                          textColor,
                        ),
                        if (widget.isChannel && _section4.isNotEmpty) ...[
                          Divider(height: 1, indent: 22, endIndent: 22, color: dividerColor),
                          // §4 (channel second): flat.
                          _buildRightsSection(null, _section4, accentColor, textColor),
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
                  // Dismiss is shown for an existing admin but NEVER for the
                  // chat creator (edit_participant_box.cpp:554).
                  if (widget.member.role == 'admin' && !_isTargetCreator) ...[
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
                ];
                return ListView.builder(
                  padding: EdgeInsets.zero,
                shrinkWrap: true,
                  itemCount: _lvKids.length,
                  itemBuilder: (_, _lvI) => _lvKids[_lvI],
                );
              }),
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

  // A flag section. When [nestingLabel] is null the flags render as flat toggle
  // rows; when set, they nest inside an expandable group with a parent master
  // toggle + "checked/total" count, mirroring AyuGram's SlideWrap + AddInnerToggle
  // for "Manage messages"/"Manage stories" (edit_peer_permissions_box.cpp:724-753).
  Widget _buildRightsSection(
    String? nestingLabel,
    List<_AdminFlag> flags,
    Color accentColor,
    Color textColor,
  ) {
    if (nestingLabel == null) {
      return Column(
        children: [
          for (final flag in flags)
            _buildRightToggle(flag, accentColor, textColor),
        ],
      );
    }
    return _NestedRightsGroup(
      label: nestingLabel,
      flags: flags,
      accentColor: accentColor,
      textColor: textColor,
      // Bubble child changes up so the owner-transfer button gating
      // (_allOwnerTransferRightsSelected) recomputes on the parent.
      onChanged: () => setState(() {}),
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
      } catch (e) {
        Debug.log('admin_tools', 'final res = await context.read<EngineService>().getChatMe...: $e');
      }
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
    final bool hasSearch = _searchQuery.trim().isNotEmpty;
    // An active event-type or per-admin filter is distinct from a text search
    // (AyuGram lng_admin_log_no_results_search vs _filter,
    // history_admin_log_inner.cpp:608).
    final bool hasFilter = (_activeChecks?.values.any((v) => v == false) ?? false) ||
        (_selectedAdminIds != null);
    final String title;
    final String description;

    if (hasSearch) {
      title = 'No actions found';
      description = "No recent actions that contain '${_searchQuery.trim()}' have been found.";
    } else if (hasFilter) {
      title = 'No actions found';
      description = 'No recent actions that match the selected filter were found.';
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
          child: GestureDetector(
            // Tap-through to the acting user's profile, mirroring AyuGram's
            // ClickHandler on the actor name (history_admin_log_inner.cpp:710).
            onTap: () {
              if (event.userId != 0 && InfoPanel.pushUserProfileRequest != null) {
                InfoPanel.pushUserProfileRequest!(
                    MemberInfo(userId: '${event.userId}', displayName: event.userName));
              }
            },
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
                // Rich sub-content: rights diffs, invite links, reaction lists.
                ..._richExtras(accentColor),
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

  // ── Structured-data accessors for rich rendering ──
  String get _target => event.actionData['target'] as String? ?? '';
  String get _link => event.actionData['link'] as String? ?? '';

  // set / removed / changed phrasing from an old→new string pair.
  String _changedRemoved(String noun) {
    if (event.newValue.isEmpty && event.oldValue.isNotEmpty) return 'removed the $noun';
    if (event.oldValue.isEmpty && event.newValue.isNotEmpty) return 'set the $noun';
    return 'changed the $noun';
  }

  static String _fmtDuration(int seconds) {
    if (seconds <= 0) return '0s';
    if (seconds % 86400 == 0) return '${seconds ~/ 86400}d';
    if (seconds % 3600 == 0) return '${seconds ~/ 3600}h';
    if (seconds % 60 == 0) return '${seconds ~/ 60}m';
    return '${seconds}s';
  }

  // Unix-timestamp → short date+time, mirroring AyuGram's langDateTime() used in
  // the invite-link / restriction "until" diffs (history_admin_log_item.cpp:505).
  static String _fmtDate(int ts) {
    if (ts <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  // "forever" / "until <date>" suffix for restriction verbs
  // (GeneratePermissionsChangeText, history_admin_log_item.cpp:362-396).
  static String _restrictUntilText(int until) {
    if (until <= 0) return ''; // 0 == forever
    return ' until ${_fmtDate(until)}';
  }

  // Topic title/closed/hidden change list for edit_topic; AyuGram emits one
  // service message per changed facet (createEditTopic, :1842).
  List<String> get _topicChanges {
    final d = event.actionData;
    final title = d['topic_title'] as String? ?? '';
    final prevTitle = d['prev_title'] as String? ?? '';
    final out = <String>[];
    if (title != prevTitle) {
      if (prevTitle.isEmpty) {
        out.add(title.isEmpty ? 'changed a topic' : 'changed a topic to "$title"');
      } else {
        out.add('changed topic "$prevTitle" to "$title"');
      }
    }
    final q = title.isNotEmpty ? ' "$title"' : '';
    final prevClosed = d['prev_closed'] == true;
    final newClosed = d['new_closed'] == true;
    if (prevClosed != newClosed) {
      out.add(newClosed ? 'closed topic$q' : 'reopened topic$q');
    }
    final prevHidden = d['prev_hidden'] == true;
    final newHidden = d['new_hidden'] == true;
    if (prevHidden != newHidden) {
      out.add(newHidden ? 'hid topic$q' : 'unhid topic$q');
    }
    return out;
  }

  // change_usernames: distinguishes reorder / activate / deactivate / single /
  // generic, mirroring createChangeUsernames (history_admin_log_item.cpp:1731).
  ({String desc, List<String> newList, List<String> prevList}) _usernamesChange() {
    final d = event.actionData;
    final prev = (d['prev_usernames'] as List?)?.cast<String>() ?? const <String>[];
    final next = (d['new_usernames'] as List?)?.cast<String>() ?? const <String>[];
    String linkUrl(String u) => 't.me/$u';
    // Same size.
    if (next.length == prev.length) {
      if (next.length == 1) {
        final p = prev.first, n = next.first;
        if (n.isEmpty && p.isNotEmpty) return (desc: 'removed the link', newList: const [], prevList: const []);
        if (p.isEmpty && n.isNotEmpty) return (desc: 'set the link', newList: const [], prevList: const []);
        return (desc: 'changed the link', newList: const [], prevList: const []);
      }
      final wasReordered = next.every((l) => prev.contains(l));
      if (wasReordered) {
        return (
          desc: 'reordered the list of links',
          newList: next.map(linkUrl).toList(),
          prevList: prev.map(linkUrl).toList(),
        );
      }
    } else if ((next.length - prev.length).abs() == 1) {
      final activated = next.length > prev.length;
      final larger = activated ? next : prev;
      final smaller = activated ? prev : next;
      final changed = larger.firstWhere((l) => !smaller.contains(l), orElse: () => '');
      return (
        desc: activated ? 'activated the link ${linkUrl(changed)}' : 'deactivated the link ${linkUrl(changed)}',
        newList: const [],
        prevList: const [],
      );
    }
    // Generic fallback.
    return (
      desc: 'changed the list of links',
      newList: next.map(linkUrl).toList(),
      prevList: prev.map(linkUrl).toList(),
    );
  }

  // Field-level invite-link diff (label / expiry / usage / approval), mirroring
  // GenerateInviteLinkChangeText (history_admin_log_item.cpp:521-553).
  List<Widget> _inviteEditDiffLines(Color accentColor) {
    final d = event.actionData;
    final out = <Widget>[];
    Widget diff(String label) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(label, style: TextStyle(fontSize: 12, color: subTextColor)),
        );
    final prevTitle = d['prev_title'] as String? ?? '';
    final newTitle = d['new_title'] as String? ?? '';
    if (prevTitle != newTitle) {
      out.add(diff('Label: ${prevTitle.isEmpty ? "—" : prevTitle} → ${newTitle.isEmpty ? "—" : newTitle}'));
    }
    final prevExp = (d['prev_expire'] as num?)?.toInt() ?? 0;
    final newExp = (d['new_expire'] as num?)?.toInt() ?? 0;
    if (prevExp != newExp) {
      final a = prevExp == 0 ? 'Never' : _fmtDate(prevExp);
      final b = newExp == 0 ? 'Never' : _fmtDate(newExp);
      out.add(diff('Expiry: $a → $b'));
    }
    final prevUse = (d['prev_usage'] as num?)?.toInt() ?? 0;
    final newUse = (d['new_usage'] as num?)?.toInt() ?? 0;
    if (prevUse != newUse) {
      final a = prevUse == 0 ? 'Unlimited' : '$prevUse';
      final b = newUse == 0 ? 'Unlimited' : '$newUse';
      out.add(diff('Usage limit: $a → $b'));
    }
    final prevReq = d['prev_request_needed'] == true;
    final newReq = d['new_request_needed'] == true;
    if (prevReq != newReq) {
      out.add(diff(newReq ? 'Request to join: enabled' : 'Request to join: disabled'));
    }
    if (out.isEmpty) return out;
    return [Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: out),
    )];
  }

  // Plain extra-line list (topic secondary changes, username link lists).
  Widget _extraLine(String text) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(text, style: TextStyle(fontSize: 12, color: subTextColor)),
      );

  Widget _linkListBlock(String? heading, List<String> links, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (heading != null && heading.isNotEmpty)
            Text(heading, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accentColor)),
          for (final l in links)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(l, style: TextStyle(fontSize: 12, color: accentColor, decoration: TextDecoration.underline)),
            ),
        ],
      ),
    );
  }

  // Per-flag labels for the restriction / admin-rights diffs.
  static const _bannedLabels = {
    'send_plain': 'Send messages', 'send_media': 'Send media',
    'send_photos': 'Send photos', 'send_videos': 'Send videos',
    'send_roundvideos': 'Send video messages', 'send_audios': 'Send music',
    'send_voices': 'Send voice messages', 'send_docs': 'Send files',
    'send_stickers': 'Send stickers', 'send_gifs': 'Send GIFs',
    'send_games': 'Send games', 'send_inline': 'Use inline bots',
    'embed_links': 'Embed links', 'send_polls': 'Send polls',
    'invite_users': 'Add members', 'manage_topics': 'Manage topics',
    'pin_messages': 'Pin messages', 'change_info': 'Change info',
    'view_messages': 'Read messages', 'edit_rank': 'Edit own tags',
  };
  static const _adminLabels = {
    'change_info': 'Change info', 'post_messages': 'Post messages',
    'edit_messages': 'Edit messages', 'delete_messages': 'Delete messages',
    'ban_users': 'Ban users', 'invite_users': 'Add users',
    'pin_messages': 'Pin messages', 'manage_topics': 'Manage topics',
    'add_admins': 'Add admins', 'anonymous': 'Remain anonymous',
    'manage_call': 'Manage video chats', 'post_stories': 'Post stories',
    'edit_stories': 'Edit stories', 'delete_stories': 'Delete stories',
    'manage_direct': 'Manage direct messages', 'manage_ranks': 'Edit member tags',
  };

  // Returns the (added, removed) right labels between two bool maps.
  static (List<String>, List<String>) _rightsDiff(
      Map? prev, Map? next, Map<String, String> labels) {
    final added = <String>[];
    final removed = <String>[];
    for (final entry in labels.entries) {
      final p = (prev?[entry.key] == true);
      final n = (next?[entry.key] == true);
      if (n && !p) added.add(entry.value);
      if (p && !n) removed.add(entry.value);
    }
    return (added, removed);
  }

  // Rich sub-content beyond the header line: rights diffs, clickable invite
  // links, reaction lists.
  List<Widget> _richExtras(Color accentColor) {
    final out = <Widget>[];
    // Rights diffs for ban/admin/default-rights.
    if (event.action == 'participant_ban' || event.action == 'change_default_rights') {
      final (added, removed) = _rightsDiff(
          event.actionData['prev_banned'] as Map?,
          event.actionData['new_banned'] as Map?,
          _bannedLabels);
      // For restrictions, an "added ban" is a removed permission.
      out.addAll(_diffLines(removed, added, accentColor, restrict: true));
    } else if (event.action == 'participant_admin') {
      final (added, removed) = _rightsDiff(
          event.actionData['prev_admin'] as Map?,
          event.actionData['new_admin'] as Map?,
          _adminLabels);
      out.addAll(_diffLines(added, removed, accentColor, restrict: false));
    } else if (event.action == 'participant_invite') {
      // GenerateParticipantChangeText with no old participant: the invited
      // user's CURRENT rights render as a diff from empty
      // (history_admin_log_item.cpp:1152, 609-639).
      final type = event.actionData['inv_type'] as String? ?? 'member';
      if (type == 'admin') {
        final (added, removed) =
            _rightsDiff(null, event.actionData['new_admin'] as Map?, _adminLabels);
        out.addAll(_diffLines(added, removed, accentColor, restrict: false));
      } else if (type == 'restricted' || type == 'banned') {
        final (added, removed) =
            _rightsDiff(null, event.actionData['new_banned'] as Map?, _bannedLabels);
        out.addAll(_diffLines(removed, added, accentColor, restrict: true));
      }
    }
    // edit_topic: title change is the header; closed/hidden changes render as
    // extra lines (createEditTopic emits 1–3 messages, :1842).
    if (event.action == 'edit_topic') {
      final changes = _topicChanges;
      if (changes.length > 1) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [for (final c in changes.skip(1)) _extraLine(c)],
          ),
        ));
      }
    }
    // change_usernames: render the new link list (+ previous order for reorder
    // and the generic fallback), createChangeUsernames (:1735-1816).
    if (event.action == 'change_usernames') {
      final u = _usernamesChange();
      if (u.newList.isNotEmpty) {
        out.add(_linkListBlock(null, u.newList, accentColor));
      }
      if (u.prevList.isNotEmpty) {
        out.add(_linkListBlock('Previous order', u.prevList, accentColor));
      }
    }
    // invite_edit: field-level label/expiry/usage/approval diff.
    if (event.action == 'invite_edit') {
      out.addAll(_inviteEditDiffLines(accentColor));
    }
    // Clickable invite link.
    if (_link.isNotEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: GestureDetector(
          onTap: () => Clipboard.setData(ClipboardData(text: _link)),
          child: Text(_link,
              style: TextStyle(fontSize: 12, color: accentColor, decoration: TextDecoration.underline)),
        ),
      ));
    }
    // Reaction list (mode == some).
    final reactions = (event.actionData['reactions_list'] as List?)?.cast<String>();
    if (event.action == 'change_reactions' && reactions != null && reactions.isNotEmpty) {
      final emojiOnly = reactions.where((r) => int.tryParse(r) == null).toList();
      if (emojiOnly.isNotEmpty) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(emojiOnly.join(' '), style: const TextStyle(fontSize: 16)),
        ));
      }
    }
    return out;
  }

  List<Widget> _diffLines(List<String> added, List<String> removed, Color accentColor,
      {required bool restrict}) {
    final out = <Widget>[];
    Widget line(String sign, String label, Color color) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('$sign $label', style: TextStyle(fontSize: 12, color: color)),
        );
    for (final a in added) {
      out.add(line('+', a, const Color(0xFF4CAF50)));
    }
    for (final r in removed) {
      out.add(line('−', r, const Color(0xFFE57373)));
    }
    if (out.isEmpty) return out;
    return [Padding(padding: const EdgeInsets.only(top: 4), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: out,
    ))];
  }

  String _actionDescription() {
    final memberLabel = isChannel ? 'subscriber' : 'member';
    switch (event.action) {
      case 'change_title':
        // Title is never "removed" (always non-empty), but keep the diff phrase.
        return 'changed the ${isChannel ? 'channel' : 'group'} title';
      case 'change_about':
        return '${_changedRemoved("description")} of the ${isChannel ? 'channel' : 'group'}';
      case 'change_username':
        return '${_changedRemoved("link")} of the ${isChannel ? 'channel' : 'group'}';
      case 'change_photo':
        return (event.actionData['photo_removed'] == true)
            ? 'removed the ${isChannel ? 'channel' : 'group'} photo'
            : 'changed the ${isChannel ? 'channel' : 'group'} photo';
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
      case 'participant_invite': {
        final name = _target.isNotEmpty ? _target : (event.detail.isNotEmpty ? event.detail : 'a $memberLabel');
        // Verb varies by the invited participant's CURRENT type — admin →
        // promoted, banned/restricted → restricted, else → invited
        // (GenerateParticipantChangeText, history_admin_log_item.cpp:642-689).
        final type = event.actionData['inv_type'] as String? ?? 'member';
        final until = (event.actionData['inv_until'] as num?)?.toInt() ?? 0;
        switch (type) {
          case 'admin':
            return 'promoted $name';
          case 'banned':
            return 'banned $name${_restrictUntilText(until)}';
          case 'restricted':
            return 'restricted $name${_restrictUntilText(until)}';
          default:
            return 'invited $name';
        }
      }
      case 'participant_ban': {
        final name = _target.isNotEmpty ? _target : (event.detail.isNotEmpty ? event.detail : 'a $memberLabel');
        final newMember = event.actionData['new_member'];
        if (newMember == false) return 'removed $name';
        return 'changed restrictions for $name';
      }
      case 'participant_admin': {
        final name = _target.isNotEmpty ? _target : (event.detail.isNotEmpty ? event.detail : 'a $memberLabel');
        final hadAdmin = (event.actionData['prev_admin'] as Map?)?.values.any((v) => v == true) ?? false;
        final hasAdmin = (event.actionData['new_admin'] as Map?)?.values.any((v) => v == true) ?? false;
        if (!hadAdmin && hasAdmin) return 'promoted $name';
        if (hadAdmin && !hasAdmin) return 'removed admin rights from $name';
        return 'changed admin rights for $name';
      }
      case 'change_stickerset':
        return (event.actionData['stickerset_removed'] == true)
            ? 'removed the group sticker set'
            : 'changed the group sticker set';
      case 'toggle_prehistory':
        return 'made chat history ${event.detail}';
      case 'change_default_rights':
        return 'changed default permissions';
      case 'stop_poll':
        return 'stopped a poll';
      case 'change_linked_chat': {
        final newId = (event.actionData['linked_new'] as num?)?.toInt() ?? 0;
        return newId == 0 ? 'removed the linked chat' : 'changed the linked chat';
      }
      case 'toggle_slowmode': {
        final newSecs = (event.actionData['slow_new'] as num?)?.toInt() ?? 0;
        if (newSecs == 0) return 'disabled slow mode';
        return 'set slow mode to ${_fmtDuration(newSecs)}';
      }
      case 'start_call':
        return 'started a voice chat';
      case 'end_call':
        return 'ended a voice chat';
      case 'participant_mute':
        return 'muted ${_target.isNotEmpty ? _target : "a participant"}';
      case 'participant_unmute':
        return 'unmuted ${_target.isNotEmpty ? _target : "a participant"}';
      case 'call_setting': {
        // join_muted true ⇒ new members join muted (admin must unmute).
        final muted = event.actionData['join_muted'] == true;
        if (isChannel) {
          return muted
              ? 'disallowed unmuting themselves for new participants'
              : 'allowed unmuting themselves for new participants';
        }
        return muted
            ? 'set new members to be muted by default'
            : 'allowed new members to speak by default';
      }
      case 'join_by_invite':
        return event.actionData['via_chatlist'] == true
            ? 'joined via folder invite link'
            : 'joined via invite link';
      case 'invite_delete':
        return 'deleted an invite link';
      case 'invite_revoke':
        return 'revoked an invite link';
      case 'invite_edit':
        return 'edited an invite link';
      case 'change_ttl': {
        final prev = (event.actionData['ttl_prev'] as num?)?.toInt() ?? 0;
        final next = (event.actionData['ttl_new'] as num?)?.toInt() ?? 0;
        if (next == 0) return 'disabled the auto-delete timer';
        if (prev == 0) return 'set the auto-delete timer to ${_fmtDuration(next)}';
        return 'changed the auto-delete timer to ${_fmtDuration(next)}';
      }
      case 'toggle_noforwards':
        return '${event.detail} content protection';
      case 'send_message':
        return 'sent a message';
      case 'toggle_forum':
        return '${event.detail} forum mode';
      case 'create_topic':
        return 'created a topic';
      case 'edit_topic': {
        final changes = _topicChanges;
        return changes.isEmpty ? 'edited a topic' : changes.first;
      }
      case 'delete_topic':
        return 'deleted a topic';
      case 'pin_topic':
        return 'pinned a topic';
      case 'toggle_antispam':
        return '${event.detail} anti-spam';
      case 'change_reactions': {
        final mode = event.actionData['reactions_mode'] as String? ?? '';
        if (mode == 'none') return 'disabled reactions';
        if (mode == 'all') return 'allowed all reactions';
        return 'changed the allowed reactions';
      }
      case 'change_usernames':
        return _usernamesChange().desc;
      case 'change_peer_color': {
        final idx = (event.actionData['color_index'] as num?)?.toInt() ?? 0;
        return 'changed the name color (#$idx)';
      }
      case 'change_profile_color': {
        final idx = (event.actionData['color_index'] as num?)?.toInt() ?? 0;
        return 'changed the profile color (#$idx)';
      }
      case 'change_wallpaper':
        return 'changed wallpaper';
      case 'change_emoji_status': {
        if (event.actionData['emoji_removed'] == true) return 'removed the emoji status';
        final until = (event.actionData['emoji_until'] as num?)?.toInt() ?? 0;
        return until > 0 ? 'set a temporary emoji status' : 'set an emoji status';
      }
      case 'change_emoji_stickerset':
        return 'changed emoji sticker set';
      case 'toggle_signature_profiles':
        return '${event.detail} signature profiles';
      case 'sub_extend':
        return 'extended the subscription of ${_target.isNotEmpty ? _target : "a member"}';
      case 'join_by_request': {
        final approver = event.actionData['approved_by'] as String? ?? '';
        return approver.isNotEmpty
            ? 'was accepted by $approver'
            : 'was accepted to the ${isChannel ? "channel" : "group"}';
      }
      case 'participant_volume': {
        final vol = (event.actionData['volume'] as num?)?.toInt() ?? 0;
        final pct = (vol / 100).round();
        final who = _target.isNotEmpty ? _target : 'a participant';
        return 'set $who\'s volume to $pct%';
      }
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
              child: Builder(builder: (_) {
                final _lvKids = <Widget>[
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
                ];
                return ListView.builder(
                  padding: EdgeInsets.zero,
                shrinkWrap: true,
                  itemCount: _lvKids.length,
                  itemBuilder: (_, _lvI) => _lvKids[_lvI],
                );
              }),
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
    // AyuGram falls back to startDate = startDate ? startDate : date so the arc
    // still draws for links that have only an expireDate
    // (edit_peer_invite_links.cpp:130).
    final start = startDate > 0 ? startDate : date;
    if (expireDate > 0 && start > 0 && expireDate > start) {
      expProg = (now - start) / (expireDate - start);
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

  static String _twoDigit(int n) => n.toString().padLeft(2, '0');

  String get statusText {
    final parts = <String>[];
    if (usage > 0) {
      parts.add('$usage joined');
    } else if (usageLimit > 0) {
      // "can join: N" line for an unused link with a usage cap
      // (ComputeStatus, edit_peer_invite_links.cpp:169).
      parts.add('can join: $usageLimit');
    }
    if (usageLimit > 0 && usage > 0) parts.add('${usageLimit - usage} remaining');
    // requested-to-join count (edit_peer_invite_links.cpp:189).
    if (requested > 0) parts.add('requested: $requested');
    if (expireDate > 0) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final remaining = expireDate - now;
      if (remaining > 0) {
        if (remaining > 86400) {
          parts.add('${remaining ~/ 86400}d left');
        } else {
          // <24h: AyuGram shows the absolute local time-of-day, not a relative
          // countdown (edit_peer_invite_links.cpp:208).
          final dt = DateTime.fromMillisecondsSinceEpoch(expireDate * 1000);
          parts.add('expires at ${_twoDigit(dt.hour)}:${_twoDigit(dt.minute)}');
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

enum _LinkColorState { permanent, expiring, expireSoon, expired, revoked, subscription }

_LinkColorState _linkColorState(_InviteLinkData d) {
  if (d.revoked) return _LinkColorState.revoked;
  // Subscription links have a distinct color regardless of progress
  // (Color::Subscription, edit_peer_invite_links.cpp:40).
  if (d.subscriptionCredits > 0) return _LinkColorState.subscription;
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
    case _LinkColorState.subscription:
      return palette.msgFile2Bg;
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
    // inner = size - 2*st::inviteLinkIconSkip (7px on the default ~44px row icon),
    // so the solid fill leaves a thin ring for the progress arc rather than the
    // arbitrary 0.55 radius (edit_peer_invite_links.cpp:742).
    final skip = size.width * (7.0 / 44.0);
    canvas.drawCircle(Offset(r, r), r - skip, icon);

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
  // Pagination cursors — the server returns a slice keyed off the last link's
  // (date, url), so many-link chats load incrementally on scroll
  // (LinksController::loadMoreRows, edit_peer_invite_links.cpp:495-538).
  static const int _kLinksPage = 100;
  bool _hasMoreActive = false;
  bool _hasMoreRevoked = false;
  bool _loadingMore = false;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadAll();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore) return;
    if (!_hasMoreActive && !_hasMoreRevoked) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) {
      _loadMore();
    }
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
        } catch (e) {
          Debug.log('admin_tools', 'admins = await engine.getAdminsWithInvites(widget.account...: $e');
        }
      }
      if (mounted) {
        setState(() {
          _activeLinks = active.map(_InviteLinkData.fromMap).toList();
          _revokedLinks = revoked.map(_InviteLinkData.fromMap).toList();
          _adminsWithInvites = admins;
          _hasMoreActive = active.length >= _kLinksPage;
          _hasMoreRevoked = revoked.length >= _kLinksPage;
          _loadingMore = false;
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

  // Loads the next slice — active links first, then revoked once active is
  // exhausted — using the last loaded link as the (offset_date, offset_link)
  // cursor (appendSlice, edit_peer_invite_links.cpp:520-538).
  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    final engine = context.read<EngineService>();
    try {
      if (_hasMoreActive && _activeLinks.isNotEmpty) {
        final last = _activeLinks.last;
        final more = await engine.getExportedChatInvites(widget.accountId, widget.chatId,
            adminId: widget.adminId, offsetDate: last.date, offsetLink: last.link);
        final seen = _activeLinks.map((l) => l.link).toSet();
        final fresh = more.map(_InviteLinkData.fromMap).where((l) => !seen.contains(l.link)).toList();
        if (mounted) {
          setState(() {
            _activeLinks.addAll(fresh);
            _hasMoreActive = more.length >= _kLinksPage && fresh.isNotEmpty;
            _loadingMore = false;
          });
        }
      } else if (_hasMoreRevoked && _revokedLinks.isNotEmpty) {
        final last = _revokedLinks.last;
        final more = await engine.getExportedChatInvites(widget.accountId, widget.chatId,
            revoked: true, adminId: widget.adminId, offsetDate: last.date, offsetLink: last.link);
        final seen = _revokedLinks.map((l) => l.link).toSet();
        final fresh = more.map(_InviteLinkData.fromMap).where((l) => !seen.contains(l.link)).toList();
        if (mounted) {
          setState(() {
            _revokedLinks.addAll(fresh);
            _hasMoreRevoked = more.length >= _kLinksPage && fresh.isNotEmpty;
            _loadingMore = false;
          });
        }
      } else if (mounted) {
        setState(() => _loadingMore = false);
      }
    } catch (e) {
      if (mounted) setState(() => _loadingMore = false);
      Debug.log('admin_tools', '_loadMore invite links: $e');
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
                : Builder(builder: (_) {
                  // Lazy builders (not pre-materialized widgets) so rows are
                  // only constructed as they scroll into view, matching the
                  // virtual peer-list pattern (edit_peer_invite_links.cpp:450).
                  final activeNonPerm = _activeLinks.where((l) => !l.permanent).toList();
                  final builders = <Widget Function()>[
                      ..._buildPermanentLink(palette, textColor, subColor).map((w) => () => w),
                      () => _buildCreateButton(palette, textColor),
                      if (activeNonPerm.isNotEmpty) ...[
                        () => _buildSectionHeader('My Links', textColor, subColor),
                        ...activeNonPerm.map((l) => () => _buildLinkRow(l, palette, textColor, subColor)),
                      ],
                      if (_revokedLinks.isNotEmpty) ...[
                        () => _buildRevokedHeader(textColor, subColor),
                        ..._revokedLinks.map((l) => () => _buildLinkRow(l, palette, textColor, subColor)),
                      ],
                      if (_adminsWithInvites.isNotEmpty) ...[
                        () => _buildSectionHeader('Other Admins', textColor, subColor),
                        ..._adminsWithInvites.map((a) => () => _buildAdminRow(a, palette, textColor, subColor)),
                      ],
                      if (_loadingMore)
                        () => const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                            ),
                    ];
                  return ListView.builder(
                    controller: _scroll,
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: builders.length,
                    itemBuilder: (_, i) => builders[i](),
                  );
                }),
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
        child: GestureDetector(
          // Permanent-link context menu with Revoke, guarded by !admin->isBot()
          // (edit_peer_invite_links.cpp:1308).
          onSecondaryTapDown: (d) => _showPermanentLinkMenu(link, d.globalPosition),
          onLongPress: () => _showPermanentLinkMenu(link, null),
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
      ),
    ];
  }

  void _showPermanentLinkMenu(_InviteLinkData link, Offset? pos) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showMenu<String>(
      context: context,
      color: isDark ? const Color(0xFF1E2C3A) : Colors.white,
      position: pos != null
          ? RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy)
          : const RelativeRect.fromLTRB(80, 160, 80, 160),
      items: [
        const PopupMenuItem(value: 'copy', child: Text('Copy')),
        // Revoke regenerates the permanent link; hidden for bot-created links.
        if (!link.adminIsBot)
          const PopupMenuItem(value: 'revoke', child: Text('Revoke')),
      ],
    ).then((v) {
      if (v == 'copy') {
        Clipboard.setData(ClipboardData(text: link.link));
        if (mounted) showTelegramToast(context, 'Link copied');
      } else if (v == 'revoke') {
        _revokeLink(link);
      }
    });
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
  bool _loadingMoreJoined = false;
  int _joinedTotal = 0;
  final Set<String> _processing = {};

  // Pagination: kFirstPage=20 then kPerPage=100 (edit_peer_invite_link.cpp:898).
  static const _kFirstPage = 20;
  static const _kPerPage = 100;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final engine = context.read<EngineService>();
    try {
      final res = await engine.getInviteImporters(widget.accountId, widget.chatId, widget.link.link,
          limit: _kFirstPage);
      if (mounted) {
        setState(() {
          _joined = (res['importers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _joinedTotal = (res['count'] as num?)?.toInt() ?? _joined.length;
          _loadingJoined = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingJoined = false);
    }
    // The requesters sub-list is shown whenever requested>0, not only when the
    // needApproval flag is set (edit_peer_invite_link.cpp:879).
    if (widget.link.requested > 0 || widget.link.needApproval) {
      if (mounted) setState(() => _loadingRequests = true);
      try {
        final res = await engine.getInviteImporters(widget.accountId, widget.chatId, widget.link.link,
            requested: true, limit: _kPerPage);
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

  // Loads the next page of joined importers using the last user as the cursor.
  Future<void> _loadMoreJoined() async {
    if (_loadingMoreJoined || _joined.length >= _joinedTotal || _joined.isEmpty) return;
    setState(() => _loadingMoreJoined = true);
    final engine = context.read<EngineService>();
    try {
      final last = _joined.last;
      final res = await engine.getInviteImporters(widget.accountId, widget.chatId, widget.link.link,
          limit: _kPerPage,
          offsetUserId: last['user_id'] as String? ?? '',
          offsetDate: (last['date'] as num?)?.toInt() ?? 0);
      final more = (res['importers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (mounted) {
        setState(() {
          _joined.addAll(more);
          _loadingMoreJoined = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMoreJoined = false);
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
                      // Conditional expiry/usage status label (red "expired",
                      // grey "Expires at…"/"already used") — edit_peer_invite_link.cpp:531.
                      _buildStatusLabel(link, palette, textColor, subColor),
                      const SizedBox(height: 8),
                      // Reactivate button for expired, non-revoked, non-bot links
                      // (AddReactivateLinkButton, edit_peer_invite_link.cpp:573).
                      if (!link.revoked && !link.adminIsBot && link.progress >= 1.0 &&
                          link.expireDate > 0 && widget.onEdit != null)
                        TextButton.icon(
                          onPressed: widget.onEdit,
                          icon: Icon(Icons.refresh, size: 18, color: palette.windowBgActive),
                          label: Text('Reactivate Link', style: TextStyle(color: palette.windowBgActive)),
                        ),
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
                      // Requests to join: shown whenever requested>0, regardless
                      // of the needApproval flag (edit_peer_invite_link.cpp:879).
                      if (link.requested > 0 || link.needApproval) ...[
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
                      else ...[
                        for (final m in _joined)
                          _importerRow(m, palette, textColor, subColor, isRequest: false),
                        if (_joined.length < _joinedTotal)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: _loadingMoreJoined
                                ? const Center(
                                    child: SizedBox(
                                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                                : TextButton(
                                    onPressed: _loadMoreJoined,
                                    child: Text('Show more (${_joinedTotal - _joined.length})',
                                        style: TextStyle(color: palette.windowBgActive)),
                                  ),
                          ),
                      ],
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

  // Conditional status line: red "expired", grey "Expires at…"/"already used",
  // or nothing (edit_peer_invite_link.cpp:531).
  Widget _buildStatusLabel(_InviteLinkData link, TelegramPalette palette, Color textColor, Color subColor) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final usedUp = link.usageLimit > 0 && link.usage >= link.usageLimit;
    final expired = link.expireDate > 0 && link.expireDate <= now;
    String? text;
    Color color = subColor;
    if (link.revoked) {
      return const SizedBox.shrink();
    } else if (expired) {
      text = 'Expired';
      color = palette.attentionButtonFg;
    } else if (usedUp) {
      text = 'Limit reached';
      color = palette.attentionButtonFg;
    } else if (link.expireDate > 0) {
      final dt = DateTime.fromMillisecondsSinceEpoch(link.expireDate * 1000);
      text = 'Expires at ${_InviteLinkData._twoDigit(dt.hour)}:${_InviteLinkData._twoDigit(dt.minute)} '
          'on ${dt.year}-${_InviteLinkData._twoDigit(dt.month)}-${_InviteLinkData._twoDigit(dt.day)}';
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(text, style: TextStyle(fontSize: 12, color: color)),
    );
  }

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

  static const _baseExpireOptions = <int, String>{
    0: 'Never',
    3600: '1 hour',
    86400: '1 day',
    604800: '7 days',
    -1: 'Custom',
  };

  static const _baseUsageOptions = <int, String>{
    0: 'Unlimited',
    1: '1 use',
    10: '10 uses',
    100: '100 uses',
    -1: 'Custom',
  };

  // Dynamic option maps: AyuGram inserts the existing link's non-preset expiry /
  // usage value into the preset list (in sorted position) so editing a 25-use
  // or odd-expiry link keeps the exact value instead of dropping it
  // (edit_invite_link.cpp:238-263).
  late Map<int, String> _expireOptions = Map.of(_baseExpireOptions);
  late Map<int, String> _usageOptions = Map.of(_baseUsageOptions);

  int _customExpireSeconds = 0;
  int _customUsageLimit = 0;

  static String _fmtExpireSeconds(int s) {
    if (s % 604800 == 0) return '${s ~/ 604800} week${s == 604800 ? '' : 's'}';
    if (s % 86400 == 0) return '${s ~/ 86400} day${s == 86400 ? '' : 's'}';
    if (s % 3600 == 0) return '${s ~/ 3600} hour${s == 3600 ? '' : 's'}';
    return '${s ~/ 60} min';
  }

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
        if (_baseExpireOptions.containsKey(dur)) {
          _expireOption = dur;
        } else {
          // Insert the exact remaining duration as its own selectable preset
          // (absolute, not a fuzzy 10% match) so it isn't lost.
          final inserted = <int, String>{};
          var done = false;
          for (final e in _baseExpireOptions.entries) {
            // Place before the first finite preset that exceeds dur (and before
            // the Custom entry).
            if (!done && e.key > 0 && e.key > dur) {
              inserted[dur] = _fmtExpireSeconds(dur);
              done = true;
            }
            if (!done && e.key == -1) {
              inserted[dur] = _fmtExpireSeconds(dur);
              done = true;
            }
            inserted[e.key] = e.value;
          }
          _expireOptions = inserted;
          _expireOption = dur;
        }
      } else {
        _expireOption = 0;
      }
      if (_baseUsageOptions.containsKey(el.usageLimit)) {
        _usageLimitOption = el.usageLimit;
      } else if (el.usageLimit > 0) {
        // Insert the exact usage limit (e.g. 25) into the preset list.
        final inserted = <int, String>{};
        var done = false;
        for (final e in _baseUsageOptions.entries) {
          if (!done && e.key > 0 && e.key > el.usageLimit) {
            inserted[el.usageLimit] = '${el.usageLimit} uses';
            done = true;
          }
          if (!done && e.key == -1) {
            inserted[el.usageLimit] = '${el.usageLimit} uses';
            done = true;
          }
          inserted[e.key] = e.value;
        }
        _usageOptions = inserted;
        _usageLimitOption = el.usageLimit;
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
  bool _isGigagroup = false;
  // Anti-spam toggle lives above the Admins list (the participant-list box's
  // "above" widget), NOT in the edit-peer box (edit_participants_box.cpp:1352).
  bool _antispamEnabled = false;
  bool _antispamLoaded = false;
  bool _isMegagroup = false;
  int _antispamMin = 100;
  // Participant count, used to gate the anti-spam toggle below the size threshold
  // (AyuGram: channel->membersCount() < min, menu_antispam_validator.cpp:86-90).
  int _memberCount = 0;

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
          _isGigagroup = flags['is_gigagroup'] == true;
          _isMegagroup = flags['is_megagroup'] == true;
          _antispamEnabled = flags['antispam'] == true;
          _antispamMin = (flags['antispam_group_size_min'] as num?)?.toInt() ?? 100;
          _memberCount = (flags['member_count'] as num?)?.toInt() ?? 0;
          _antispamLoaded = true;
        });
      }
    } catch (e) {
      Debug.log('admin_tools', 'final flags = await context.read<EngineService>().getChat...: $e');
    }
  }

  // The "Aggressive Anti-Spam" toggle rendered above the Admins list
  // (the participant-list box's "above" widget, edit_participants_box.cpp:1352).
  // Megagroups only, and only above the size threshold from appConfig.
  Widget? _antiSpamHeader() {
    if (!_antispamLoaded || widget.isChannel || !_isMegagroup) return null;
    final palette = PaletteProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    // AyuGram disables the toggle below appConfig telegram_antispam_group_size_min
    // (menu_antispam_validator.cpp:86-90): channel->membersCount() < min → locked,
    // and a tap fires lng_manage_peer_antispam_not_enough.
    final belowThreshold = _memberCount < _antispamMin;
    final notEnoughMsg = 'Aggressive filtering can be enabled only in groups with '
        'more than $_antispamMin ${_antispamMin == 1 ? 'member' : 'members'}.';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Aggressive Anti-Spam',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: belowThreshold ? subTextColor : textColor)),
              ),
              // Below threshold the toggle is locked (greyed); tapping it surfaces
              // the "not enough members" toast rather than silently failing server-side.
              GestureDetector(
                onTap: belowThreshold ? () => showTelegramToast(context, notEnoughMsg) : null,
                child: Opacity(
                  opacity: belowThreshold ? 0.45 : 1.0,
                  child: Switch(
                    value: _antispamEnabled,
                    activeColor: palette.windowBgActive,
                    onChanged: belowThreshold ? null : _toggleAntiSpam,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 2),
            child: Text(
              'Telegram will filter more spam but may occasionally affect ordinary messages. '
              'You can report False Positives in Recent Actions.',
              style: TextStyle(fontSize: 12, color: subTextColor),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleAntiSpam(bool value) async {
    final engine = context.read<EngineService>();
    setState(() => _antispamEnabled = value);
    try {
      await engine.toggleAntiSpam(widget.accountId, widget.chatId, value);
    } catch (e) {
      if (mounted) {
        setState(() => _antispamEnabled = !value);
        showTelegramToast(context, 'Failed: $e');
      }
    }
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
        // ParticipantsOnlineSorter: keep online members near the top (creator/
        // admins keep their natural order in the admins tab). A stable sort by
        // online status approximates the continuous 1s re-sort
        // (edit_participants_box.cpp:912).
        if (tab == _MemberTab.members) {
          final list = _members[tab]!;
          list.sort((a, b) {
            if (a.isOnline == b.isOnline) return 0;
            return a.isOnline ? -1 : 1;
          });
        }
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
            isGigagroup: _isGigagroup,
            // canAddMembers() maps to the invite-users right for a megagroup.
            canAddMembers: _canInviteUsers,
            // Anti-spam toggle is the Admins-tab "above" widget.
            header: tab == _MemberTab.admins ? _antiSpamHeader() : null,
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
  final bool isGigagroup;
  final bool canAddMembers;
  // Optional widget rendered above the list (e.g. the Admins-tab anti-spam toggle).
  final Widget? header;

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
    this.isGigagroup = false,
    this.canAddMembers = false,
    this.header,
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

    if (emptyContent && header == null) {
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
    final headerOffset = header != null ? 1 : 0;

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
        itemCount: members.length + addOffset + headerOffset + (loading ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (headerOffset == 1 && i == 0) {
            return header!;
          }
          if (hasAdd && i == headerOffset) {
            return _buildAddButton(ctx);
          }
          final memberIdx = i - addOffset - headerOffset;
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
            isGigagroup: isGigagroup,
            canAddMembers: canAddMembers,
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
    final selected = await showDialog<List<_PickerEntry>>(
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
    // Add Members (multi-select) and Ban (single) act directly; Add Admin /
    // Add Exception run the showAdmin/showRestricted pre-flight + rights editor.
    if (isMembersTab) {
      try {
        await engine.addMembers(accountId, chatId, selected.map((e) => e.id).toList());
        onRefresh();
        if (ctx.mounted) showTelegramToast(ctx, 'Done');
      } catch (e) {
        if (ctx.mounted) showTelegramToast(ctx, 'Failed: $e');
      }
      return;
    }
    final entry = selected.first;
    if (tab == _MemberTab.kicked) {
      try {
        await engine.banMember(accountId, chatId, entry.id);
        onRefresh();
        if (ctx.mounted) showTelegramToast(ctx, 'Done');
      } catch (e) {
        if (ctx.mounted) showTelegramToast(ctx, 'Failed: $e');
      }
      return;
    }
    // checkInfoLoaded: fetch the target's current status before opening the
    // editor (add_participants_box.cpp:1386-1410).
    final status = await _preflightStatus(engine, entry.id);
    if (!ctx.mounted) return;
    if (tab == _MemberTab.admins) {
      // showAdmin restriction confirmations (add_participants_box.cpp:1439-1492).
      if (status == 'kicked' || status == 'restricted') {
        if (!await _confirmAdd(ctx,
            'This user was removed from the ${isChannel ? "channel" : "group"}. Add them back as admin?')) {
          return;
        }
      } else if (status == 'external') {
        if (!await _confirmAdd(ctx,
            'Add this user to the ${isChannel ? "channel" : "group"} and promote to admin?')) {
          return;
        }
      }
      if (!ctx.mounted) return;
      final member = MemberInfo(
        userId: entry.id,
        displayName: entry.name,
        username: entry.username,
        avatarB64: entry.avatarB64,
        role: (status == 'admin' || status == 'creator') ? 'admin' : 'member',
      );
      final saved = await showEditAdminBox(ctx,
          accountId: accountId, chatId: chatId, member: member, isChannel: isChannel, isForum: isForum);
      if (saved == true) onRefresh();
    } else {
      // showRestricted: confirm before restricting an admin/creator
      // (add_participants_box.cpp:1561-1576).
      if (status == 'admin' || status == 'creator') {
        if (!await _confirmAdd(ctx, 'This user is an admin. Restrict them anyway?')) return;
      }
      if (!ctx.mounted) return;
      final member = MemberInfo(
        userId: entry.id,
        displayName: entry.name,
        username: entry.username,
        avatarB64: entry.avatarB64,
        role: (status == 'restricted' || status == 'kicked') ? 'restricted' : 'member',
      );
      final saved = await showEditRestrictedBox(ctx,
          accountId: accountId, chatId: chatId, member: member, isForum: isForum);
      if (saved == true) onRefresh();
    }
  }

  // checkInfoLoaded equivalent: returns the target's current chat status
  // (creator/admin/restricted/kicked/member) or 'external' when they are not a
  // participant (channels.getParticipant fails with USER_NOT_PARTICIPANT).
  Future<String> _preflightStatus(EngineService engine, String userId) async {
    try {
      final info = await engine.getParticipantInfo(accountId, chatId, userId);
      if (info.isEmpty) return 'external';
      final role = (info['role'] as String?) ?? '';
      return role.isEmpty ? 'member' : role;
    } catch (_) {
      return 'external';
    }
  }

  Future<bool> _confirmAdd(BuildContext ctx, String message) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('OK')),
        ],
      ),
    );
    return ok == true;
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
  // Base list shown with no query: all contacts (loaded once, filtered locally
  // like ContactsBoxController) plus a recent-participants snapshot.
  List<_PickerEntry> _contacts = [];
  List<_PickerEntry> _base = [];
  // Currently displayed rows (base list, or live search results).
  List<_PickerEntry> _filtered = [];
  // Every entry seen so far, keyed by id, so multi-select can resolve picked
  // ids back to full entries even across separate search batches.
  final Map<String, _PickerEntry> _entryById = {};
  final Set<String> _selected = {};
  bool _loading = true;
  bool _resolving = false;
  bool _searching = false;
  String _query = '';
  Timer? _debounce;
  // Debounce between keystroke and server search (AddSpecialBoxSearchController
  // AutoSearchTimeout, add_participants_box.cpp:1735).
  static const _kSearchDebounce = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _remember(Iterable<_PickerEntry> entries) {
    for (final e in entries) {
      _entryById[e.id] = e;
    }
  }

  Future<void> _load() async {
    final engine = context.read<EngineService>();
    final contacts = <String, _PickerEntry>{};
    try {
      final list = await engine.getContacts(widget.accountId);
      for (final c in list) {
        contacts[c.userId] = _PickerEntry(c.userId, c.displayName, c.username, c.avatarB64);
      }
    } catch (e) {
      Debug.log('admin_tools', 'final contacts = await engine.getContacts(widget.accountId): $e');
    }
    final base = <String, _PickerEntry>{...contacts};
    // For special-member adds, seed the no-query view with a recent-participants
    // snapshot (live per-keystroke participant search runs server-side below).
    if (widget.includeMembers) {
      try {
        final res = await engine.getChatMembersByRole(widget.accountId, widget.chatId,
            role: 'members', limit: 100);
        for (final m in res.members) {
          base[m.userId] = _PickerEntry(m.userId, m.displayName, m.username, m.avatarB64);
        }
      } catch (e) {
        Debug.log('admin_tools', 'final res = await engine.getChatMembersByRole(widget.acco...: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _contacts = contacts.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _base = base.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _filtered = _base;
      _loading = false;
    });
    _remember(_base);
  }

  void _onSearch(String q) {
    final trimmed = q.trim();
    _query = trimmed;
    _debounce?.cancel();
    if (trimmed.isEmpty) {
      setState(() {
        _searching = false;
        _filtered = _base;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(_kSearchDebounce, () => _runSearch(trimmed));
  }

  // Debounced per-keystroke search: server-side participant search first
  // (ChannelParticipantsSearch), then local contact matches, then offer global
  // resolve — AddSpecialBoxSearchController order participants → contacts →
  // global (add_participants_box.cpp:1775-1797).
  Future<void> _runSearch(String q) async {
    final engine = context.read<EngineService>();
    final ql = q.toLowerCase();
    final byId = <String, _PickerEntry>{};
    // 1. Server-side participant search (skipped for the contacts-only Add
    // Members picker, which mirrors ContactsBoxController).
    if (widget.includeMembers) {
      try {
        final res = await engine.getChatMembersByRole(widget.accountId, widget.chatId,
            role: 'members', query: q, limit: 50);
        for (final m in res.members) {
          byId[m.userId] = _PickerEntry(m.userId, m.displayName, m.username, m.avatarB64);
        }
      } catch (e) {
        Debug.log('admin_tools', '_runSearch participants: $e');
      }
    }
    // A newer keystroke superseded this request — drop the stale result.
    if (!mounted || q != _query) return;
    // 2. Local contact matches (full contact list is already loaded).
    for (final c in _contacts) {
      if (c.name.toLowerCase().contains(ql) || c.username.toLowerCase().contains(ql)) {
        byId.putIfAbsent(c.id, () => c);
      }
    }
    final results = byId.values.toList();
    _remember(results);
    setState(() {
      _filtered = results;
      _searching = false;
    });
  }

  // Resolves a username not in the participant/contact results and adds it
  // (global search step — contacts.resolveUsername).
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
        } catch (e) {
          Debug.log('admin_tools', 'final p = await engine.getUserProfile(widget.accountId, id): $e');
        }
        final entry = _PickerEntry(id, name, q, '');
        _remember([entry]);
        if (mounted) {
          setState(() {
            _filtered = [entry];
            _resolving = false;
          });
        }
        return;
      }
    } catch (e) {
      Debug.log('admin_tools', 'final p = await engine.getUserProfile(widget.accountId, id): $e');
    }
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
      final entry = _entryById[id] ?? _PickerEntry(id, id, '', '');
      Navigator.pop(context, [entry]);
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
                if (_filtered.isEmpty && !_searching) _resolveGlobal();
              },
            ),
            // Thin progress bar while a debounced server search is in flight.
            SizedBox(
              height: 2,
              child: _searching ? const LinearProgressIndicator(minHeight: 2) : null,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_searching ? 'Searching…' : 'No matches', style: TextStyle(color: subColor)),
                              if (_query.isNotEmpty && !_searching) ...[
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
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.pop(context,
                    _selected.map((id) => _entryById[id] ?? _PickerEntry(id, id, '', '')).toList()),
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
  // Gating for the kicked/restricted actions (edit_participants_box.cpp).
  final bool isGigagroup;
  final bool canAddMembers;

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
    this.isGigagroup = false,
    this.canAddMembers = false,
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
        // Real last-seen string (Data::OnlineText) instead of a static "offline"
        // fallback (edit_participants_box.cpp:2421).
        return _lastSeenText(member.lastSeenKind, member.lastSeenTs);
    }
  }

  static String _lastSeenText(String kind, int ts) {
    if (kind == 'recently') return 'last seen recently';
    if (kind == 'within_week') return 'last seen within a week';
    if (kind == 'within_month') return 'last seen within a month';
    if (kind == 'long_time_ago') return 'last seen a long time ago';
    if (ts > 0) {
      final now = DateTime.now();
      final seen = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      final diff = now.difference(seen);
      if (diff.inMinutes < 1) return 'last seen just now';
      if (diff.inMinutes < 60) return 'last seen ${diff.inMinutes} min ago';
      if (diff.inHours < 24) return 'last seen ${diff.inHours}h ago';
      if (diff.inDays == 1) return 'last seen yesterday';
      return 'last seen ${diff.inDays} days ago';
    }
    return 'last seen recently';
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
      } catch (e) {
        Debug.log('admin_tools', 'final bytes = base64Decode(member.avatarB64): $e');
      }
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
      // Restrict-without-kick requires a megagroup that is NOT a gigagroup
      // (isMegagroup && !isGigagroup) — broadcast channels and gigagroups have
      // no restrict path (edit_participants_box.cpp:1975).
      if (!isChannel && !isGigagroup && member.canRestrict && !member.isCreator && !member.isSelf) {
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
      // "Add to group" (unkick + re-add) is gated on isMegagroup && canAddMembers
      // — a broadcast channel can't re-add removed users
      // (edit_participants_box.cpp:1946). "Delete" just removes from the removed
      // list (unblock, no re-add).
      if (!isChannel && canAddMembers) {
        items.add(const PopupMenuItem(value: 'add_to_group', child: Text('Add to Group')));
      }
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

  // rowClicked: admins/members tab opens the admin editor (or short info for a
  // non-editable target); restricted opens the restriction editor; kicked opens
  // the user profile (edit_participants_box.cpp:1753).
  void _rowClicked(BuildContext context) {
    switch (tab) {
      case _MemberTab.admins:
      case _MemberTab.members:
        if (member.canEditAdmin && !member.isCreator) {
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
          return;
        }
        break;
      case _MemberTab.restricted:
        if (member.canRestrict) {
          showEditRestrictedBox(context, accountId: accountId, chatId: chatId, member: member)
              .then((changed) {
            if (changed == true) onRefresh();
          });
          return;
        }
        break;
      default:
        break;
    }
    // Fallback: open the member's profile (short info box).
    if (InfoPanel.pushUserProfileRequest != null) {
      InfoPanel.pushUserProfileRequest!(member);
    }
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
              } catch (e) {
                Debug.log('admin_tools', 'await engine.removeMember(accountId, chatId, member.userId): $e');
              }
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
    } catch (e) {
      Debug.log('admin_tools', 'await engine.unbanChatMember(accountId, chatId, member.us...: $e');
    }
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
      // rowClicked: opens the short-info / admin / restricted editor depending
      // on the tab (edit_participants_box.cpp:1753). Previously only right-click
      // and long-press were wired.
      onTap: isRequest ? null : () => _rowClicked(context),
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
  // Recent posts: show the first 10, then "Show more" loads 30 at a time
  // (info_statistics_inner_widget.cpp:868).
  int _recentShown = 10;

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

  // Localized overview labels (lng_stats_overview_*) instead of title-casing the
  // raw JSON keys (info_statistics_inner_widget.cpp:483).
  static const _statLabels = {
    'followers': 'Followers',
    'enabled_notifications': 'Enabled Notifications',
    'views_per_post': 'Views Per Post',
    'views_per_story': 'Views Per Story',
    'shares_per_post': 'Shares Per Post',
    'shares_per_story': 'Shares Per Story',
    'reactions_per_post': 'Reactions Per Post',
    'reactions_per_story': 'Reactions Per Story',
    'members': 'Members',
    'messages': 'Messages',
    'viewers': 'Active Members',
    'posters': 'Active Posters',
  };

  // Fixed overview ordering: channel = members/notifications%/meanView/meanStoryView
  // (info_statistics_inner_widget.cpp:425); the second block is the story stats
  // (:724). Megagroup = members/messages/viewers/posters (:498).
  static const _channelBlock1 = ['followers', 'enabled_notifications', 'views_per_post', 'views_per_story'];
  static const _channelBlock2 = ['shares_per_post', 'shares_per_story', 'reactions_per_post', 'reactions_per_story'];
  static const _groupBlock = ['members', 'messages', 'viewers', 'posters'];

  static String _humanize(String key) {
    return _statLabels[key] ??
        key.split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }

  // Lang::FormatCountToShort: 1.2K / 3.4M (info_statistics_inner_widget.cpp uses
  // the short form for overview values, chart_rulers_data.cpp:29).
  static String _fmtShort(num v) {
    final a = v.abs();
    String body;
    if (a >= 1000000) {
      body = '${(v / 1000000).toStringAsFixed(a % 1000000 == 0 ? 0 : 1)}M';
    } else if (a >= 1000) {
      body = '${(v / 1000).toStringAsFixed(a % 1000 == 0 ? 0 : 1)}K';
    } else {
      body = v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
    }
    return body;
  }

  // FormatDateTime(ItemDateTime(item)) — includes the time component
  // (info_statistics_recent_message.cpp:82).
  static String _fmtDateTime(int epochSec) {
    if (epochSec <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} ${d.year}, $hh:$mm';
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

      // Build a card from a single overview key (ordered, localized, with the
      // absolute-diff growth badge). Returns null when the key is absent.
      _StatCard? cardFor(String key) {
        final val = data[key];
        num? current;
        num? previous;
        if (val is Map) {
          if (val['current'] is num) current = val['current'] as num;
          if (val['previous'] is num) previous = val['previous'] as num;
        } else if (val is num) {
          current = val;
        }
        if (current == null) return null;
        final isPct = key == 'enabled_notifications';
        return _StatCard(
          label: _humanize(key),
          value: isPct ? '${current.toStringAsFixed(2)}%' : _fmtShort(current),
          current: current,
          previous: previous,
          isPct: isPct,
          cardColor: cardColor,
          textColor: textColor,
          subTextColor: subTextColor,
        );
      }

      // Fixed 2×2 overview grid (+ a second story-stats block for channels).
      final isGroupStats = data.containsKey('members') && data.containsKey('messages');
      final overview = <Widget>[];
      final overview2 = <Widget>[];
      if (isGroupStats) {
        for (final k in _groupBlock) {
          final c = cardFor(k);
          if (c != null) overview.add(c);
        }
      } else {
        for (final k in _channelBlock1) {
          final c = cardFor(k);
          if (c != null) overview.add(c);
        }
        for (final k in _channelBlock2) {
          final c = cardFor(k);
          if (c != null) overview2.add(c);
        }
      }
      // Any remaining unknown keys still render (forward-compatibility).
      for (final entry in data.entries) {
        final key = entry.key;
        if (key == 'charts' || key == 'recent_posts' || key == 'period_min' || key == 'period_max' ||
            key == 'top_posters' || key == 'top_admins' || key == 'top_inviters' ||
            _statLabels.containsKey(key)) {
          continue;
        }
        final c = cardFor(key);
        if (c != null) overview.add(c);
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

      body = Builder(builder: (_) {
        final _lvKids = <Widget>[
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
          // Second overview block — Channel Story Stats (shares/reactions per
          // post & story) — info_statistics_inner_widget.cpp:724.
          if (overview2.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text('Story Stats',
                  style: TextStyle(color: subTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(spacing: 8, runSpacing: 8, children: overview2),
            ),
          ],
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
            ...recentPosts.whereType<Map>().take(_recentShown).map((p) => _RecentPostRow(
                  post: p,
                  accountId: widget.accountId,
                  chatId: widget.chatId,
                  cardColor: cardColor,
                  textColor: textColor,
                  subTextColor: subTextColor,
                  accentColor: accentColor,
                )),
            if (recentPosts.length > _recentShown)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: TextButton(
                  onPressed: () => setState(() => _recentShown += 30),
                  child: Text('Show more (${recentPosts.length - _recentShown})',
                      style: TextStyle(color: accentColor)),
                ),
              ),
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
        ];
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: _lvKids.length,
          itemBuilder: (_, _lvI) => _lvKids[_lvI],
        );
      });
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
  final num? current;
  final num? previous;
  final bool isPct;
  final Color cardColor;
  final Color textColor;
  final Color subTextColor;

  const _StatCard({
    required this.label,
    required this.value,
    this.current,
    this.previous,
    this.isPct = false,
    required this.cardColor,
    required this.textColor,
    required this.subTextColor,
  });

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.of(context).size.width - 24 - 8) / 2;
    // Growth badge: AyuGram shows "+N (X%)" with the absolute diff via
    // FormatCountToShort and the U+2212 minus glyph for negatives
    // (info_statistics_inner_widget.cpp:344).
    String? badge;
    Color badgeColor = subTextColor;
    if (current != null && previous != null && previous! > 0 && current != previous) {
      final diff = current! - previous!;
      final pct = (diff / previous! * 100).abs();
      final up = diff > 0;
      final absStr = _StatisticsScreenState._fmtShort(diff.abs());
      // U+2212 minus glyph for negatives; '+' for positives.
      badge = '${up ? '+' : '−'}$absStr (${pct.toStringAsFixed(pct >= 10 ? 0 : 1)}%)';
      badgeColor = up ? const Color(0xFF4FAD2D) : const Color(0xFFE53935);
    }
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
              if (badge != null) ...[
                const SizedBox(width: 6),
                Text(badge,
                    style: TextStyle(color: badgeColor, fontSize: 13, fontWeight: FontWeight.w600)),
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
      builder: (_) => _MessageStatsScreen(
        accountId: accountId,
        chatId: chatId,
        msgId: msgId,
        views: post['views'] as int? ?? 0,
        forwards: post['forwards'] as int? ?? 0,
        reactions: post['reactions'] as int? ?? 0,
      ),
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
                    // Name line: preview + right-aligned views (AyuGram puts the
                    // view count at the name-line right edge,
                    // info_statistics_recent_message.cpp:256).
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(preview,
                              style: TextStyle(color: textColor, fontSize: 14),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        Text('${_StatisticsScreenState._fmtShort(views)} views',
                            style: TextStyle(color: subTextColor, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Status line: date + right-aligned shares(+icon)/reactions(+icon).
                    Row(
                      children: [
                        if (date > 0)
                          Text(_StatisticsScreenState._fmtDateTime(date),
                              style: TextStyle(color: subTextColor, fontSize: 11)),
                        const Spacer(),
                        Icon(Icons.share_outlined, size: 13, color: subTextColor),
                        const SizedBox(width: 2),
                        Text(_StatisticsScreenState._fmtShort(forwards),
                            style: TextStyle(color: subTextColor, fontSize: 12)),
                        const SizedBox(width: 10),
                        Icon(Icons.favorite_border, size: 13, color: subTextColor),
                        const SizedBox(width: 2),
                        Text(_StatisticsScreenState._fmtShort(reactions),
                            style: TextStyle(color: subTextColor, fontSize: 12)),
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
  // x-axis epoch-ms values, for the adaptive bottom date caption (PaintBottomLine,
  // chart_widget.cpp:100).
  final List<int> xValues;

  _StatChart(this.title, this.series, this.names, this.colors, this.kind, {this.xValues = const []});

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
      final xValues = <int>[];
      for (final col in columns) {
        if (col is! List || col.isEmpty) continue;
        final id = col.first.toString();
        if (id == 'x' || types[id] == 'x') {
          // Capture the x-axis timestamps for the bottom date labels.
          for (var i = 1; i < col.length; i++) {
            final v = col[i];
            xValues.add(v is num ? v.toInt() : 0);
          }
          continue;
        }
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
      return _StatChart(title, series, seriesNames, seriesColors, _kindFor(type, types), xValues: xValues);
    } catch (_) {
      return null;
    }
  }

  // ~5 evenly spaced date captions across the x range (adaptive bottom line).
  List<String> _xLabels() {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const count = 5;
    final out = <String>[];
    final n = xValues.length;
    for (var i = 0; i < count; i++) {
      final idx = ((n - 1) * i / (count - 1)).round().clamp(0, n - 1);
      final ms = xValues[idx];
      if (ms <= 0) {
        out.add('');
        continue;
      }
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      out.add('${d.day} ${months[d.month - 1]}');
    }
    return out;
  }

  // Date+time caption for the crosshair tooltip header at a given x index.
  String xLabelAt(int idx) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (idx < 0 || idx >= xValues.length) return '';
    final ms = xValues[idx];
    if (ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  List<String> xLabels() => _xLabels();

  // Compact axis/tooltip number format (1.2K / 3.4M), matching AyuGram's
  // ChartHorizontalLinesData label shortener (chart_horizontal_lines_data.cpp).
  static String formatValue(double v) {
    final a = v.abs();
    String s;
    if (a >= 1000000) {
      s = '${(v / 1000000).toStringAsFixed(v.abs() >= 10000000 ? 0 : 1)}M';
    } else if (a >= 1000) {
      s = '${(v / 1000).toStringAsFixed(v.abs() >= 10000 ? 0 : 1)}K';
    } else if (v == v.roundToDouble()) {
      s = v.toInt().toString();
    } else {
      s = v.toStringAsFixed(1);
    }
    return s.replaceAll('.0K', 'K').replaceAll('.0M', 'M');
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
        } catch (e) {
          Debug.log('admin_tools', 'final loaded = await context.read<EngineService>().loadSt...: $e');
        }
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
      child: _InteractiveChart(
        accountId: widget.accountId,
        chart: _parsed!,
        zoomToken: widget.chart['zoom_token'] as String? ?? '',
        cardColor: widget.cardColor,
        textColor: widget.textColor,
        subTextColor: widget.subTextColor,
      ),
    );
  }
}

// Interactive statistics chart: line-toggle filter (tap legend), hover/touch
// crosshair tooltip, animated Y-axis rulers with value labels, a draggable
// footer range-selector, and click-to-zoom (StatsLoadAsyncGraph with the clicked
// x). Mirrors AyuGram ChartWidget + ChartLinesFilterWidget + ChartRulersView
// (statistics/chart_widget.cpp, view/chart_rulers_view.cpp).
class _InteractiveChart extends StatefulWidget {
  final String accountId;
  final _StatChart chart;
  final String zoomToken;
  final Color cardColor;
  final Color textColor;
  final Color subTextColor;
  const _InteractiveChart({
    required this.accountId,
    required this.chart,
    required this.zoomToken,
    required this.cardColor,
    required this.textColor,
    required this.subTextColor,
  });

  @override
  State<_InteractiveChart> createState() => _InteractiveChartState();
}

class _InteractiveChartState extends State<_InteractiveChart>
    with SingleTickerProviderStateMixin {
  // Series toggled off via the legend (ChartLinesFilterWidget).
  final Set<int> _hidden = {};
  // Crosshair selection index into the visible window (-1 = none).
  int _selectedIndex = -1;
  // Footer range window as fractions [0,1] of the full x range.
  double _rangeStart = 0;
  double _rangeEnd = 1;
  // Animated Y max so rulers slide when toggling lines (ChartRulersView).
  late AnimationController _animCtrl;
  double _animMaxFrom = 1, _animMaxTo = 1;
  double _shownMax = 1;

  // Zoom state: when set, we render the fetched zoomed (e.g. hourly) chart with
  // a "Zoom Out" affordance.
  _StatChart? _zoomed;
  bool _zooming = false;

  _StatChart get _chart => _zoomed ?? widget.chart;
  bool get _isLine => _chart.kind == _ChartKind.line;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
      ..addListener(() {
        setState(() {
          _shownMax = _animMaxFrom + (_animMaxTo - _animMaxFrom) * _animCtrl.value;
        });
      });
    _shownMax = _animMaxTo = _computeMax();
  }

  @override
  void didUpdateWidget(_InteractiveChart old) {
    super.didUpdateWidget(old);
    if (old.chart != widget.chart) {
      _hidden.clear();
      _zoomed = null;
      _selectedIndex = -1;
      _rangeStart = 0;
      _rangeEnd = 1;
      _shownMax = _animMaxTo = _computeMax();
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  int get _maxLen {
    var m = 0;
    for (final s in _chart.series) {
      if (s.length > m) m = s.length;
    }
    return m;
  }

  // [i0,i1] integer x-window from the range fractions.
  (int, int) get _window {
    final n = _maxLen;
    if (n < 2) return (0, n - 1 < 0 ? 0 : n - 1);
    final i0 = (_rangeStart * (n - 1)).floor().clamp(0, n - 1);
    final i1 = (_rangeEnd * (n - 1)).ceil().clamp(0, n - 1);
    return (i0, i1 < i0 ? i0 : i1);
  }

  // Max across visible series within the window — drives the rulers.
  double _computeMax() {
    final (i0, i1) = _window;
    double maxV = 0;
    if (_chart.kind == _ChartKind.stackedBar ||
        _chart.kind == _ChartKind.bar ||
        _chart.kind == _ChartKind.stackedArea) {
      for (var i = i0; i <= i1; i++) {
        double sum = 0;
        for (var si = 0; si < _chart.series.length; si++) {
          if (_hidden.contains(si)) continue;
          final s = _chart.series[si];
          if (i < s.length) sum += s[i];
        }
        if (sum > maxV) maxV = sum;
      }
    } else {
      for (var si = 0; si < _chart.series.length; si++) {
        if (_hidden.contains(si)) continue;
        final s = _chart.series[si];
        for (var i = i0; i <= i1 && i < s.length; i++) {
          if (s[i] > maxV) maxV = s[i];
        }
      }
    }
    return maxV <= 0 ? 1 : maxV;
  }

  void _animateToMax() {
    final target = _computeMax();
    if ((target - _animMaxTo).abs() < 1e-9) return;
    _animMaxFrom = _shownMax;
    _animMaxTo = target;
    _animCtrl
      ..reset()
      ..forward();
  }

  void _toggleSeries(int i) {
    setState(() {
      if (_hidden.contains(i)) {
        _hidden.remove(i);
      } else if (_hidden.length < _chart.series.length - 1) {
        // Never hide the last visible line (AyuGram keeps ≥1 enabled).
        _hidden.add(i);
      }
      _selectedIndex = -1;
    });
    _animateToMax();
  }

  void _onHover(Offset local, Size size) {
    final n = _maxLen;
    if (n < 2) return;
    final (i0, i1) = _window;
    final span = (i1 - i0);
    if (span <= 0) return;
    final frac = (local.dx / size.width).clamp(0.0, 1.0);
    final idx = (i0 + frac * span).round().clamp(i0, i1);
    if (idx != _selectedIndex) setState(() => _selectedIndex = idx);
  }

  void _clearHover() {
    if (_selectedIndex != -1) setState(() => _selectedIndex = -1);
  }

  Future<void> _zoomAt(int idx) async {
    if (widget.zoomToken.isEmpty || _zoomed != null || _zooming) return;
    if (idx < 0 || idx >= widget.chart.xValues.length) return;
    final ms = widget.chart.xValues[idx];
    if (ms <= 0) return;
    setState(() => _zooming = true);
    try {
      // StatsLoadAsyncGraph wants the x in seconds (zoomRequests fire(x), then
      // requestZoom(token, x) — info_statistics_inner_widget.cpp:154).
      final loaded = await context
          .read<EngineService>()
          .loadStatsGraph(widget.accountId, widget.zoomToken, x: ms ~/ 1000);
      final data = loaded['data'];
      _StatChart? zoomed;
      if (data is String && data.isNotEmpty) {
        zoomed = _StatChart.parse(widget.chart.title, data,
            type: (loaded['type'] as String?) ?? 'Linear');
      }
      if (!mounted) return;
      setState(() {
        _zooming = false;
        if (zoomed != null) {
          _zoomed = zoomed;
          _hidden.clear();
          _selectedIndex = -1;
          _rangeStart = 0;
          _rangeEnd = 1;
          _shownMax = _animMaxTo = _computeMax();
        }
      });
    } catch (e) {
      Debug.log('admin_tools', 'chart zoom: $e');
      if (mounted) setState(() => _zooming = false);
    }
  }

  void _zoomOut() {
    setState(() {
      _zoomed = null;
      _hidden.clear();
      _selectedIndex = -1;
      _rangeStart = 0;
      _rangeEnd = 1;
      _shownMax = _animMaxTo = _computeMax();
    });
  }

  @override
  Widget build(BuildContext context) {
    final chart = _chart;
    final (i0, i1) = _window;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: widget.cardColor, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(chart.title,
                    style: TextStyle(color: widget.textColor, fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              if (_zooming)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              if (_zoomed != null && !_zooming)
                GestureDetector(
                  onTap: _zoomOut,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.zoom_out, size: 16, color: widget.subTextColor),
                    const SizedBox(width: 2),
                    Text('Zoom Out', style: TextStyle(color: widget.subTextColor, fontSize: 12)),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Main interactive plot.
          RepaintBoundary(
            child: SizedBox(
              height: 160,
              width: double.infinity,
              child: LayoutBuilder(builder: (ctx, c) {
                final size = Size(c.maxWidth, c.maxHeight);
                return MouseRegion(
                  onHover: (e) => _onHover(e.localPosition, size),
                  onExit: (_) => _clearHover(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) {
                      _onHover(d.localPosition, size);
                    },
                    onTapUp: (_) {
                      if (_isLine && widget.zoomToken.isNotEmpty && _zoomed == null && _selectedIndex >= 0) {
                        _zoomAt(_selectedIndex);
                      }
                    },
                    onHorizontalDragUpdate: (d) => _onHover(d.localPosition, size),
                    onHorizontalDragEnd: (_) => _clearHover(),
                    child: CustomPaint(
                      painter: _InteractiveChartPainter(
                        series: chart.series,
                        colors: chart.colors,
                        kind: chart.kind,
                        hidden: _hidden,
                        i0: i0,
                        i1: i1,
                        maxY: _shownMax,
                        selectedIndex: _selectedIndex,
                        rulerColor: widget.subTextColor.withValues(alpha: 0.18),
                        labelColor: widget.subTextColor,
                        crosshairColor: widget.subTextColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          // Crosshair tooltip.
          if (_selectedIndex >= 0) _buildTooltip(),
          // Adaptive bottom date caption row (PaintBottomLine, chart_widget.cpp:100).
          if (chart.xValues.length >= 2)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final t in chart.xLabels())
                    Text(t, style: TextStyle(color: widget.subTextColor, fontSize: 10)),
                ],
              ),
            ),
          // Footer range-selector (only meaningful for time-series with width).
          if (_maxLen >= 8 && _zoomed == null) _buildRangeSelector(),
          const SizedBox(height: 8),
          // Toggleable legend (ChartLinesFilterWidget).
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: List.generate(chart.names.length, (i) {
              final off = _hidden.contains(i);
              return GestureDetector(
                onTap: () => _toggleSeries(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: off ? Colors.transparent : chart.colors[i].withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: chart.colors[i].withValues(alpha: off ? 0.4 : 0.0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(off ? Icons.circle_outlined : Icons.check_circle,
                          size: 12, color: chart.colors[i]),
                      const SizedBox(width: 4),
                      Text(chart.names[i],
                          style: TextStyle(
                              color: off ? widget.subTextColor : widget.textColor, fontSize: 12)),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTooltip() {
    final chart = _chart;
    final idx = _selectedIndex;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: widget.subTextColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(chart.xLabelAt(idx),
              style: TextStyle(color: widget.textColor, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          for (var si = 0; si < chart.series.length; si++)
            if (!_hidden.contains(si) && idx < chart.series[si].length)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8,
                        decoration: BoxDecoration(color: chart.colors[si], shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text('${chart.names[si]}: ',
                        style: TextStyle(color: widget.subTextColor, fontSize: 12)),
                    Text(_StatChart.formatValue(chart.series[si][idx]),
                        style: TextStyle(color: widget.textColor, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  // Footer overview strip with two draggable handles defining the visible
  // window (ChartWidget::Footer, chart_widget.cpp range selector).
  Widget _buildRangeSelector() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        height: 34,
        child: LayoutBuilder(builder: (ctx, c) {
          final w = c.maxWidth;
          void setFromDx(double dx, bool isStart) {
            final f = (dx / w).clamp(0.0, 1.0);
            setState(() {
              if (isStart) {
                _rangeStart = f.clamp(0.0, _rangeEnd - 0.08);
              } else {
                _rangeEnd = f.clamp(_rangeStart + 0.08, 1.0);
              }
            });
            _animateToMax();
          }

          final left = _rangeStart * w;
          final right = _rangeEnd * w;
          return Stack(
            children: [
              // Faint full-range overview.
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _InteractiveChartPainter(
                      series: _chart.series,
                      colors: _chart.colors,
                      kind: _chart.kind,
                      hidden: _hidden,
                      i0: 0,
                      i1: _maxLen - 1,
                      maxY: _computeFullMax(),
                      selectedIndex: -1,
                      rulerColor: Colors.transparent,
                      labelColor: Colors.transparent,
                      crosshairColor: Colors.transparent,
                      overview: true,
                    ),
                  ),
                ),
              ),
              // Dim the excluded sides.
              Positioned(left: 0, top: 0, bottom: 0, width: left,
                  child: Container(color: widget.subTextColor.withValues(alpha: 0.18))),
              Positioned(left: right, right: 0, top: 0, bottom: 0,
                  child: Container(color: widget.subTextColor.withValues(alpha: 0.18))),
              // Window border.
              Positioned(
                left: left, width: (right - left).clamp(0.0, w), top: 0, bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: widget.subTextColor.withValues(alpha: 0.6), width: 1.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              // Left handle.
              Positioned(
                left: (left - 11).clamp(0.0, w), top: 0, bottom: 0, width: 22,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (d) => setFromDx((d.globalPosition.dx) - _localOriginX(ctx), true),
                  child: Center(child: Container(width: 4, height: 18, decoration: BoxDecoration(color: widget.subTextColor, borderRadius: BorderRadius.circular(2)))),
                ),
              ),
              // Right handle.
              Positioned(
                left: (right - 11).clamp(0.0, w), top: 0, bottom: 0, width: 22,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (d) => setFromDx((d.globalPosition.dx) - _localOriginX(ctx), false),
                  child: Center(child: Container(width: 4, height: 18, decoration: BoxDecoration(color: widget.subTextColor, borderRadius: BorderRadius.circular(2)))),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  double _localOriginX(BuildContext ctx) {
    final box = ctx.findRenderObject();
    if (box is RenderBox) return box.localToGlobal(Offset.zero).dx;
    return 0;
  }

  double _computeFullMax() {
    final saved0 = _rangeStart, saved1 = _rangeEnd;
    _rangeStart = 0;
    _rangeEnd = 1;
    final m = _computeMax();
    _rangeStart = saved0;
    _rangeEnd = saved1;
    return m;
  }
}

// Renders the visible x-window [i0,i1] of the (non-hidden) series against a
// shared 0..maxY scale, drawing labeled Y-axis rulers (ChartRulersView) and an
// optional crosshair. `overview:true` paints just the lines for the footer
// range-selector strip (no rulers/labels/crosshair).
class _InteractiveChartPainter extends CustomPainter {
  final List<List<double>> series;
  final List<Color> colors;
  final _ChartKind kind;
  final Set<int> hidden;
  final int i0;
  final int i1;
  final double maxY;
  final int selectedIndex;
  final Color rulerColor;
  final Color labelColor;
  final Color crosshairColor;
  final bool overview;

  _InteractiveChartPainter({
    required this.series,
    required this.colors,
    required this.kind,
    required this.hidden,
    required this.i0,
    required this.i1,
    required this.maxY,
    required this.selectedIndex,
    required this.rulerColor,
    required this.labelColor,
    required this.crosshairColor,
    this.overview = false,
  });

  Color _colorAt(int i) => i < colors.length ? colors[i] : const Color(0xFF50A2E9);

  bool _visible(int si) => !hidden.contains(si);

  double _xOf(int i, Size size) {
    final span = i1 - i0;
    if (span <= 0) return 0;
    return size.width * (i - i0) / span;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty || i1 < i0) return;
    final m = maxY <= 0 ? 1.0 : maxY;

    // Y-axis rulers with per-level value labels (ChartRulersView, animated via
    // the maxY the state interpolates — chart_rulers_view.cpp).
    if (!overview && rulerColor.a > 0) {
      final guide = Paint()
        ..color = rulerColor
        ..strokeWidth = 1;
      const rulers = 5;
      for (var g = 0; g < rulers; g++) {
        final frac = g / (rulers - 1);
        final y = size.height - frac * size.height;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), guide);
        if (labelColor.a > 0) {
          final value = m * frac;
          final tp = TextPainter(
            text: TextSpan(
              text: _StatChart.formatValue(value),
              style: TextStyle(color: labelColor, fontSize: 10),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final ly = (y - tp.height - 1).clamp(0.0, size.height - tp.height);
          tp.paint(canvas, Offset(0, ly));
        }
      }
    }

    switch (kind) {
      case _ChartKind.bar:
      case _ChartKind.stackedBar:
        _paintBars(canvas, size, m);
        break;
      case _ChartKind.stackedArea:
        _paintStackedArea(canvas, size, m);
        break;
      case _ChartKind.line:
        _paintLines(canvas, size, m);
        break;
    }

    // Crosshair + per-series dots at the selected index.
    if (!overview && selectedIndex >= i0 && selectedIndex <= i1 && crosshairColor.a > 0) {
      final x = _xOf(selectedIndex, size);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height),
          Paint()..color = crosshairColor..strokeWidth = 1);
      if (kind == _ChartKind.line) {
        for (var si = 0; si < series.length; si++) {
          if (!_visible(si)) continue;
          final s = series[si];
          if (selectedIndex >= s.length) continue;
          final y = size.height - (s[selectedIndex] / m).clamp(0.0, 1.0) * size.height;
          canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = _colorAt(si));
          canvas.drawCircle(Offset(x, y), 3.5,
              Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
        }
      }
    }
  }

  void _paintLines(Canvas canvas, Size size, double m) {
    for (var si = 0; si < series.length; si++) {
      if (!_visible(si)) continue;
      final s = series[si];
      if (s.length < 2) continue;
      final paint = Paint()
        ..color = _colorAt(si)
        ..style = PaintingStyle.stroke
        ..strokeWidth = overview ? 1 : 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      final path = Path();
      var started = false;
      for (var i = i0; i <= i1 && i < s.length; i++) {
        final x = _xOf(i, size);
        final y = size.height - (s[i] / m).clamp(0.0, 1.0) * size.height;
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  // Stacked vertical bars within the window, scaled to the shared max.
  void _paintBars(Canvas canvas, Size size, double m) {
    final cols = i1 - i0 + 1;
    if (cols < 1) return;
    final slot = size.width / cols;
    final barW = slot * (overview ? 0.9 : 0.8);
    for (var i = i0; i <= i1; i++) {
      var yTop = size.height;
      final x = (i - i0) * slot + (slot - barW) / 2;
      for (var si = 0; si < series.length; si++) {
        if (!_visible(si)) continue;
        final s = series[si];
        if (i >= s.length) continue;
        final h = (s[i] / m).clamp(0.0, 1.0) * size.height;
        if (h <= 0) continue;
        canvas.drawRect(Rect.fromLTWH(x, yTop - h, barW, h), Paint()..color = _colorAt(si));
        yTop -= h;
      }
    }
  }

  // Stacked filled areas within the window.
  void _paintStackedArea(Canvas canvas, Size size, double m) {
    if (i1 - i0 < 1) return;
    final cumulative = <int, double>{};
    for (var si = 0; si < series.length; si++) {
      if (!_visible(si)) continue;
      final s = series[si];
      final path = Path();
      var started = false;
      for (var i = i0; i <= i1; i++) {
        final v = i < s.length ? s[i] : 0;
        final x = _xOf(i, size);
        final base = cumulative[i] ?? 0;
        final y = size.height - ((base + v) / m).clamp(0.0, 1.0) * size.height;
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      for (var i = i1; i >= i0; i--) {
        final x = _xOf(i, size);
        final base = cumulative[i] ?? 0;
        final y = size.height - (base / m).clamp(0.0, 1.0) * size.height;
        path.lineTo(x, y);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = _colorAt(si).withValues(alpha: 0.75));
      for (var i = i0; i <= i1; i++) {
        cumulative[i] = (cumulative[i] ?? 0) + (i < s.length ? s[i] : 0);
      }
    }
  }

  @override
  bool shouldRepaint(_InteractiveChartPainter old) {
    return old.kind != kind ||
        old.i0 != i0 ||
        old.i1 != i1 ||
        old.maxY != maxY ||
        old.selectedIndex != selectedIndex ||
        old.hidden.length != hidden.length ||
        old.series.length != series.length ||
        old.overview != overview;
  }
}

// Per-message statistics (AyuGram messageStatistic) — opened by tapping a
// recent post. Shows the message's interaction graphs + public-shares count.
class _MessageStatsScreen extends StatefulWidget {
  final String accountId;
  final String chatId;
  final int msgId;
  // Per-message scalar stats (from the recent-post row) for the overview cards:
  // views / publicForwards / reactions / privateForwards
  // (info_statistics_inner_widget.cpp:515).
  final int views;
  final int forwards;
  final int reactions;
  const _MessageStatsScreen({
    required this.accountId,
    required this.chatId,
    required this.msgId,
    this.views = 0,
    this.forwards = 0,
    this.reactions = 0,
  });

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
      final publicForwards = data['public_forwards_count'] as int? ?? 0;
      final publicList = (data['public_forwards'] as List?) ?? const [];
      // Private forwards = total forwards − public forwards (the rest are to DMs
      // / private groups).
      final privateForwards = (widget.forwards - publicForwards).clamp(0, 1 << 31);
      Widget overviewCard(String label, int value) => Container(
            width: (MediaQuery.of(context).size.width - 24 - 8) / 2,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_StatisticsScreenState._fmtShort(value),
                    style: TextStyle(color: textColor, fontSize: 19, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(color: subTextColor, fontSize: 12)),
              ],
            ),
          );
      body = Builder(builder: (_) {
        final _lvKids = <Widget>[
          // Per-message overview cards (views / publicForwards / reactions /
          // privateForwards) — info_statistics_inner_widget.cpp:515.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              if (widget.views > 0) overviewCard('Views', widget.views),
              overviewCard('Public Shares', publicForwards),
              if (widget.reactions > 0) overviewCard('Reactions', widget.reactions),
              if (privateForwards > 0) overviewCard('Private Shares', privateForwards),
            ]),
          ),
          for (final ch in charts.whereType<Map>())
            _StatChartWidget(
              accountId: widget.accountId,
              chart: ch,
              cardColor: cardColor,
              textColor: textColor,
              subTextColor: subTextColor,
            ),
          // Paginated public-forwards list (PublicForwardsController,
          // info_statistics_inner_widget.cpp:770).
          if (publicList.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Text('Public Shares',
                  style: TextStyle(color: subTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            ...publicList.whereType<Map>().map((f) {
              final name = (f['name'] as String?)?.trim() ?? '';
              final views = f['views'] as int? ?? 0;
              return Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  Icon(f['type'] == 'story' ? Icons.auto_stories_outlined : Icons.forward_outlined,
                      size: 18, color: subTextColor),
                  const SizedBox(width: 10),
                  Expanded(child: Text(name.isNotEmpty ? name : 'Unknown',
                      style: TextStyle(color: textColor, fontSize: 14),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (views > 0)
                    Text('${_StatisticsScreenState._fmtShort(views)} views',
                        style: TextStyle(color: subTextColor, fontSize: 12)),
                ]),
              );
            }),
          ],
          if (charts.isEmpty && publicForwards == 0 && widget.views == 0)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: Text('No statistics for this message.',
                  style: TextStyle(color: subTextColor, fontSize: 14))),
            ),
        ];
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: _lvKids.length,
          itemBuilder: (_, _lvI) => _lvKids[_lvI],
        );
      });
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
  // Premium→boosts multiplier for the prepaid-giveaway badge (premium giveaways
  // gain quantity * multiplier boosts, giveawayBoostsPerPremium()).
  int _boostsPerPremium = 4;

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
    // Best-effort multiplier for the premium prepaid-giveaway boost badge.
    try {
      final cfg = await engine.getGiveawayConfig(widget.accountId);
      if (mounted && (cfg['boosts_per_premium'] ?? 0) > 0) {
        setState(() => _boostsPerPremium = cfg['boosts_per_premium']!);
      }
    } catch (e) {
      Debug.log('admin_tools', 'boosts_per_premium config: $e');
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

  void _openGiveaway({int prepaidIndex = 0}) {
    final prepaid = _status?['prepaid_giveaways'];
    final prepaidList = prepaid is List ? prepaid.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
    showCreateGiveawayBox(
      context,
      accountId: widget.accountId,
      chatId: widget.chatId,
      theme: Theme.of(context),
      prepaidGiveaways: prepaidList,
      selectedPrepaidIndex: prepaidIndex,
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
                  child: Builder(builder: (_) {
                    final premiumCount = (premiumAudience['premium'] as num?)?.toInt() ??
                        (premiumAudience['premium_count'] as num?)?.toInt() ?? 0;
                    final premiumPart = (premiumAudience['part'] as num?)?.toDouble() ?? 0;
                    final boostsToNext = (nextLevelBoosts - boosts).clamp(0, 1 << 31);
                    final _lvKids = <Widget>[
                      // FillBoostLimit bubble + limit-row bar before the overview
                      // (info_boosts_inner_widget.cpp:311).
                      Container(
                        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Bubble showing the current boost count, positioned along the bar.
                            LayoutBuilder(builder: (ctx, c) {
                              final w = c.maxWidth;
                              final left = (w * progress - 18).clamp(0.0, w - 40);
                              return SizedBox(
                                height: 28,
                                child: Stack(children: [
                                  Positioned(
                                    left: left,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                          color: accentColor, borderRadius: BorderRadius.circular(10)),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        const Icon(Icons.bolt, size: 13, color: Colors.white),
                                        Text('$boosts',
                                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                      ]),
                                    ),
                                  ),
                                ]),
                              );
                            }),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Level $level', style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600)),
                                if (nextLevelBoosts > 0)
                                  Text('Level ${level + 1}', style: TextStyle(color: subTextColor, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 8,
                                backgroundColor: subTextColor.withValues(alpha: 0.2),
                                valueColor: AlwaysStoppedAnimation(accentColor),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 4-cell overview grid: level / premium-audience / boost-count
                      // / boosts-to-next (info_boosts_inner_widget.cpp:65).
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Wrap(spacing: 8, runSpacing: 8, children: [
                          _boostStatCell('$level', 'Level',
                              cardColor, textColor, subTextColor, accentColor),
                          _boostStatCell(
                              premiumPart > 0 ? '${premiumPart.toStringAsFixed(premiumPart >= 10 ? 0 : 1)}%' : '$premiumCount',
                              'Premium audience',
                              cardColor, textColor, subTextColor, accentColor),
                          _boostStatCell('$boosts', 'Existing boosts',
                              cardColor, textColor, subTextColor, accentColor),
                          if (nextLevelBoosts > 0)
                            _boostStatCell('$boostsToNext', 'Boosts to level up',
                                cardColor, textColor, subTextColor, accentColor),
                        ]),
                      ),
                      // Invite/share-link block with an AddHeader title
                      // (lng_boosts_link_title, info_boosts_inner_widget.cpp:172).
                      if ((data['boost_url'] as String? ?? '').isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                          child: Text('LINK FOR BOOSTING',
                              style: TextStyle(color: subTextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        _buildShareLink(data['boost_url'] as String, cardColor, textColor, subTextColor, accentColor),
                      ],
                      // Prepaid giveaway rows.
                      ..._buildPrepaidGiveaways(data, cardColor, textColor, subTextColor, accentColor),
                      // Boosts / Gifts tab switcher — hidden when only one slice
                      // has data (hasOneTab, info_boosts_inner_widget.cpp:431).
                      if (_total > 0 && _giftsTotal > 0)
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
                      // Create-giveaway button, gated behind
                      // giveawayGiftsPurchaseAvailable() (info_boosts_inner_widget.cpp:232).
                      if (data['giveaway_available'] != false)
                        _buildGiveawayButton(accentColor),
                    ];
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: _lvKids.length,
                      itemBuilder: (_, _lvI) => _lvKids[_lvI],
                    );
                  }),
                ),
    );
  }

  Widget _boostStatCell(String value, String label, Color cardColor, Color textColor,
      Color subTextColor, Color accentColor) {
    return Container(
      width: (MediaQuery.of(context).size.width - 24 - 8) / 2,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(color: accentColor, fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: subTextColor, fontSize: 12)),
        ],
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
      ...prepaid.whereType<Map>().toList().asMap().entries.map((entry) {
        final idx = entry.key;
        final g = entry.value;
        final quantity = (g['quantity'] as num?)?.toInt() ?? 0;
        final months = (g['months'] as num?)?.toInt() ?? 0;
        final credits = (g['credits'] as num?)?.toInt() ?? 0;
        // PrepaidCredits (Stars) vs Prepaid (Premium) — GiveawayTypeRow type
        // (info_boosts_inner_widget.cpp:351). Stars rows show a star icon + the
        // star amount; premium rows show the subscription length.
        final isCredits = credits > 0;
        // Boost-count badge: explicit for stars, quantity * multiplier for
        // premium (info_boosts_inner_widget.cpp:374).
        final explicitBoosts = (g['boosts'] as num?)?.toInt() ?? 0;
        final boostCount = explicitBoosts > 0 ? explicitBoosts : quantity * _boostsPerPremium;
        final title = isCredits ? 'Star Giveaway' : '$quantity Telegram Premium';
        final subtitle = isCredits
            ? '$quantity ${quantity == 1 ? 'giveaway' : 'giveaways'} · $credits Stars'
            : '$months ${months == 1 ? 'month' : 'months'}';
        return InkWell(
          onTap: () => _openGiveaway(prepaidIndex: idx),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: isCredits ? const Color(0xFFE8A93B) : accentColor,
                  child: Icon(isCredits ? Icons.star : Icons.card_giftcard, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(color: textColor, fontSize: 14)),
                      Text(subtitle, style: TextStyle(color: subTextColor, fontSize: 12)),
                    ],
                  ),
                ),
                // Boost-count badge with a small boost icon (CreateBadge).
                if (boostCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt, size: 13, color: accentColor),
                        Text('$boostCount',
                            style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                const SizedBox(width: 6),
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
    final userId = booster['user_id'] as String? ?? '';
    final avatarB64 = booster['avatar_b64'] as String? ?? '';
    final isGiveaway = booster['giveaway'] == true;
    final isGift = booster['gift'] == true;
    final isUnclaimed = booster['unclaimed'] == true;
    final isCredits = booster['credits'] == true;
    final creditsAmount = (booster['stars'] as num?)?.toInt() ?? 0;
    final multiplier = booster['multiplier'] as int? ?? 0;
    // Localized special-booster names instead of hardcoded strings
    // (info_statistics_list_controllers.cpp:557).
    final displayName = (name != null && name.isNotEmpty)
        ? name
        : isCredits
            ? '$creditsAmount Stars'
            : isUnclaimed
                ? 'Unclaimed boost'
                : isGiveaway
                    ? 'To be distributed'
                    : 'Unknown user';
    final letter = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    // Status text varies by booster type: real/credits show the expiry; unclaimed
    // / pending show months + date (info_statistics_list_controllers.cpp:539).
    String status = '';
    if (dateText.isNotEmpty) {
      status = isUnclaimed ? 'Expires on $dateText' : 'boosted · expires $dateText';
    }

    // Type-colored EmptyUserpic for special boosters (icon overlay).
    Widget avatar;
    if (avatarB64.isNotEmpty) {
      try {
        avatar = CircleAvatar(radius: 18, backgroundImage: MemoryImage(base64Decode(avatarB64)));
      } catch (_) {
        avatar = _emptyUserpic(letter, isUnclaimed, isGiveaway);
      }
    } else {
      avatar = _emptyUserpic(letter, isUnclaimed, isGiveaway);
    }

    return InkWell(
      // Booster rows open peer info / gift-code resolution depending on type
      // (info_boosts_inner_widget.cpp:402). We open the booster's profile.
      onTap: userId.isEmpty
          ? null
          : () {
              if (InfoPanel.pushUserProfileRequest != null) {
                InfoPanel.pushUserProfileRequest!(MemberInfo(userId: userId, displayName: displayName));
              }
            },
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName,
                      style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (status.isNotEmpty)
                    Text(status, style: TextStyle(color: subTextColor, fontSize: 12)),
                ],
              ),
            ),
            // Styled pill badge (icon + color) as the right action
            // (info_statistics_list_controllers.cpp:588).
            if (isGiveaway || isGift)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(isGiveaway ? Icons.casino_outlined : Icons.card_giftcard,
                      size: 12, color: accentColor),
                  const SizedBox(width: 3),
                  Text(isGiveaway ? 'Giveaway' : 'Gift',
                      style: TextStyle(color: accentColor, fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
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
      ),
    );
  }

  Widget _emptyUserpic(String letter, bool unclaimed, bool giveaway) {
    // Type-colored EmptyUserpic with an icon overlay for unclaimed/unknown.
    if (unclaimed || giveaway) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: (unclaimed ? Colors.grey : accentColor).withValues(alpha: 0.85),
        child: Icon(unclaimed ? Icons.help_outline : Icons.casino_outlined, size: 18, color: Colors.white),
      );
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: accentColor.withValues(alpha: 0.85),
      child: Text(letter, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
  // Full / Incoming / Outgoing history filter ('' / 'in' / 'out'),
  // AddCreditsHistoryList tabs (info_channel_earn_list.cpp:979).
  String _txFilter = '';

  // Restrict-sponsored toggle state (broadcast channels only):
  // {is_broadcast, restricted, required_level, current_level}.
  Map<String, dynamic>? _sponsored;
  bool _settingSponsored = false;

  // TON (currency) ad-revenue — the currency side of AyuGram's earn section,
  // shown before the Stars/credits side (info_channel_earn_list.cpp:611).
  Map<String, dynamic>? _tonStats;
  bool _tonWithdrawing = false;
  final List<Map<String, dynamic>> _tonTransactions = [];
  String _tonTxOffset = '';
  bool _tonTxHasMore = true;
  bool _loadingTonTx = false;
  bool _tonTxLoadedOnce = false;

  // Drives the live withdrawal-lock countdown (AyuGram updates it every 250ms).
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final nextAt = (_stats?['next_withdrawal_at'] as num?)?.toInt() ?? 0;
      if (nextAt > DateTime.now().millisecondsSinceEpoch ~/ 1000 && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
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
    } catch (e) {
      Debug.log('admin_tools', 'final ton = await engine.getBroadcastRevenueStats(widget....: $e');
    }
    try {
      final s = await engine.getStarsRevenueStats(widget.accountId, widget.chatId);
      if (mounted) setState(() { _stats = s; _loading = false; });
      _loadMoreTransactions();
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
    // Restrict-sponsored toggle info (broadcast channels only) — best-effort.
    try {
      final sp = await engine.getSponsoredInfo(widget.accountId, widget.chatId);
      if (mounted && sp['is_broadcast'] == true) setState(() => _sponsored = sp);
    } catch (e) {
      Debug.log('admin_tools', 'getSponsoredInfo: $e');
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
  // MajorPart/MinorPart: the full 9-digit minor part with trailing-zero chopping,
  // not a truncated 2-digit value (earn_format.cpp:24).
  static String _fmtTon(int nanotons) {
    final neg = nanotons < 0;
    final abs = nanotons.abs();
    final whole = abs ~/ 1000000000;
    var minor = (abs % 1000000000).toString().padLeft(9, '0');
    // Chop trailing zeros from the minor part.
    minor = minor.replaceFirst(RegExp(r'0+$'), '');
    final s = minor.isEmpty ? '$whole' : '$whole.$minor';
    return neg ? '-$s' : s;
  }

  // For TON, usd_rate is the value of 1 TON in USD (AyuGram ToUsd: value*rate,
  // value = nanotons/1e9), unlike Stars where it's per-1000.
  static String _fmtUsdTon(int nanotons, double usdRate) {
    if (usdRate <= 0) return '';
    final usd = (nanotons / 1e9) * usdRate;
    return '≈ \$${usd.toStringAsFixed(2)}';
  }

  // Switches the Stars history filter tab (Full / Incoming / Outgoing) and
  // re-requests from the start with the new inbound/outbound flag.
  void _setTxFilter(String filter) {
    if (_txFilter == filter || _loadingTx) return;
    setState(() {
      _txFilter = filter;
      _transactions.clear();
      _txOffset = '';
      _txHasMore = true;
      _txLoadedOnce = false;
    });
    _loadMoreTransactions();
  }

  Future<void> _loadMoreTransactions() async {
    if (_loadingTx || !_txHasMore) return;
    setState(() { _loadingTx = true; _txLoadedOnce = true; });
    final engine = context.read<EngineService>();
    try {
      final res = await engine.getChannelStarsTransactions(widget.accountId, widget.chatId, offset: _txOffset, filter: _txFilter);
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

  // Withdraw flow: choose the amount (AddInputFieldForCredits, min/max gated),
  // then collect the 2FA password, fetch the withdrawal URL, open it.
  Future<void> _withdraw() async {
    if (_withdrawing) return;
    final data = _stats ?? const {};
    final available = data['available_balance'] as int? ?? 0;
    final minAmount = (data['withdrawal_min'] as num?)?.toInt() ?? 0;
    var maxAmount = (data['withdrawal_max'] as num?)?.toInt() ?? available;
    if (maxAmount <= 0 || maxAmount > available) maxAmount = available;
    final amount = await _promptWithdrawAmount(available, minAmount, maxAmount);
    if (amount == null || !mounted) return;
    final password = await _promptPassword();
    if (password == null || password.isEmpty || !mounted) return;
    setState(() => _withdrawing = true);
    final engine = context.read<EngineService>();
    try {
      final url = await engine.getStarsRevenueWithdrawalUrl(widget.accountId, widget.chatId, password, amount: amount);
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

  // Amount-to-withdraw input (AddInputFieldForCredits, settings_credits_graphics.cpp:3322).
  // Defaults to the full available balance; enforces [min, max] with the
  // stars_revenue_withdrawal_min floor and the per-withdrawal cap.
  Future<int?> _promptWithdrawAmount(int available, int minAmount, int maxAmount) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    final accentColor = PaletteProvider.of(context).windowBgActive;
    final ctrl = TextEditingController(text: '$maxAmount');
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
        String? error;
        int? parse() => int.tryParse(ctrl.text.trim());
        return AlertDialog(
          backgroundColor: bgColor,
          title: Text('Withdraw Stars', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Available: $available  •  Min: $minAmount',
                  style: TextStyle(color: subTextColor, fontSize: 13)),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.star, color: Color(0xFFFFB800), size: 20),
                  labelText: 'Amount',
                  errorText: error,
                  border: const UnderlineInputBorder(),
                ),
                onChanged: (_) => setDlg(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: subTextColor))),
            TextButton(
              onPressed: () {
                final v = parse();
                if (v == null || v <= 0) {
                  setDlg(() => error = 'Enter an amount');
                  return;
                }
                if (v < minAmount) {
                  setDlg(() => error = 'Minimum is $minAmount Stars');
                  return;
                }
                if (v > maxAmount) {
                  setDlg(() => error = 'Maximum is $maxAmount Stars');
                  return;
                }
                Navigator.pop(ctx, v);
              },
              child: Text('Continue', style: TextStyle(color: accentColor, fontWeight: FontWeight.w600)),
            ),
          ],
        );
      }),
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
    return InkWell(
      // Each transaction opens a details box (recipient/address/success link +
      // AddChannelEarnTable, info_channel_earn_list.cpp:1143).
      onTap: () => _showTxDetails(tx, label, amount, date),
      child: Container(
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
      ),
    );
  }

  void _showTxDetails(Map<String, dynamic> tx, String label, int amount, int date) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(k, style: TextStyle(color: subTextColor, fontSize: 13)),
            Flexible(child: Text(v, textAlign: TextAlign.right,
                style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500))),
          ]),
        );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text(label, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w600)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          row('Amount', '$amount Stars'),
          if (date > 0) row('Date', _txDate(date)),
          if ((tx['description'] as String?)?.isNotEmpty ?? false)
            row('Description', tx['description'] as String),
          if ((tx['id'] as String?)?.isNotEmpty ?? false)
            row('Transaction ID', tx['id'] as String),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
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
    return InkWell(
      // Each row opens a details box (recipient/address/success link +
      // AddChannelEarnTable, info_channel_earn_list.cpp:1143).
      onTap: () => _showTonTxDetails(tx, label, amount, date, usdRate, incoming),
      child: Container(
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
      ),
    );
  }

  // TON transaction details box (info_channel_earn_list.cpp:1148): amount + date,
  // an earn table of fields (recipient/provider/address), an in/out description
  // and the blockchain explorer success-link button (entry.successLink, :1244).
  void _showTonTxDetails(
      Map<String, dynamic> tx, String label, int amount, int date, double usdRate, bool incoming) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    final accentColor = PaletteProvider.of(context).windowBgActive;
    final url = (tx['transaction_url'] as String?) ?? '';
    final recipient = (tx['recipient'] as String?) ?? (tx['address'] as String?) ?? '';
    final usd = _fmtUsdTon(amount, usdRate);
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(k, style: TextStyle(color: subTextColor, fontSize: 13)),
            const SizedBox(width: 12),
            Flexible(child: Text(v, textAlign: TextAlign.right,
                style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500))),
          ]),
        );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Row(children: [
          const Icon(Icons.diamond, size: 18, color: Color(0xFF0098EA)),
          const SizedBox(width: 6),
          Text('${incoming ? '+' : ''}${_fmtTon(amount)} TON',
              style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w600)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (usd.isNotEmpty) row('Value', usd),
          if (date > 0) row('Date', _txDate(date)),
          if ((tx['description'] as String?)?.isNotEmpty ?? false)
            row('Description', tx['description'] as String),
          if (recipient.isNotEmpty) row('Recipient', recipient),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              incoming
                  ? 'Proceeds from ads shown in this channel.'
                  : 'Withdrawal to your TON wallet.',
              style: TextStyle(color: subTextColor, fontSize: 12),
            ),
          ),
        ]),
        actions: [
          if (url.isNotEmpty)
            TextButton.icon(
              icon: Icon(Icons.open_in_new, size: 16, color: accentColor),
              label: Text('View in Explorer', style: TextStyle(color: accentColor)),
              onPressed: () {
                final uri = Uri.tryParse(url);
                if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  // Full / Incoming / Outgoing slider for the Stars history.
  Widget _buildTxFilterTabs(Color cardColor, Color textColor, Color subTextColor, Color accentColor) {
    Widget tab(String label, String value) {
      final selected = _txFilter == value;
      return Expanded(
        child: InkWell(
          onTap: () => _setTxFilter(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Text(label,
                    style: TextStyle(
                        color: selected ? accentColor : subTextColor,
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
                const SizedBox(height: 4),
                Container(height: 2, color: selected ? accentColor : Colors.transparent),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        tab('All', ''),
        tab('Incoming', 'in'),
        tab('Outgoing', 'out'),
      ]),
    );
  }

  // "Restrict sponsored messages" toggle with a boost-level badge; only for
  // broadcast channels, locked below the required level (info_channel_earn_list.cpp:1391).
  List<Widget> _buildSponsoredToggle(Color cardColor, Color textColor, Color subTextColor, Color accentColor) {
    final sp = _sponsored;
    if (sp == null || sp['is_broadcast'] != true) return const [];
    final restricted = sp['restricted'] == true;
    final requiredLevel = (sp['required_level'] as num?)?.toInt() ?? 0;
    final currentLevel = (sp['current_level'] as num?)?.toInt() ?? 0;
    final locked = currentLevel < requiredLevel;
    return [
      const SizedBox(height: 18),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text('Restrict sponsored messages',
                        style: TextStyle(color: textColor, fontSize: 14)),
                  ),
                  if (requiredLevel > 0) ...[
                    const SizedBox(width: 8),
                    // Boost-level badge (AddLevelBadge).
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF8E7BEF)]),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.bolt, size: 11, color: Colors.white),
                        Text('Lv $requiredLevel',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
            if (_settingSponsored)
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Switch(
                value: restricted,
                onChanged: (v) => _toggleSponsored(v, locked, requiredLevel),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Text(
          locked
              ? 'Reach boost level $requiredLevel to switch off ads in this channel.'
              : 'Switch off ads in this channel. You will no longer earn from sponsored messages.',
          style: TextStyle(fontSize: 12, color: subTextColor, height: 1.4),
        ),
      ),
    ];
  }

  Future<void> _toggleSponsored(bool value, bool locked, int requiredLevel) async {
    if (_settingSponsored) return;
    if (locked && value) {
      // CheckBoostLevel: can't restrict ads until the channel reaches the level.
      showTelegramToast(context, 'Reach boost level $requiredLevel to restrict ads.');
      return;
    }
    setState(() => _settingSponsored = true);
    final engine = context.read<EngineService>();
    try {
      await engine.setRestrictSponsored(widget.accountId, widget.chatId, value);
      if (mounted) {
        setState(() {
          _sponsored = {...?_sponsored, 'restricted': value};
          _settingSponsored = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _settingSponsored = false);
        showTelegramToast(context, 'Failed: $e');
      }
    }
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

    // ── TON (currency) ad-revenue ── shown alongside the Stars (credits) side in
    // the combined overview (currency + credits — info_channel_earn_list.cpp:682).
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

    // Combined overview: Available / Current / Overall as three rows, each with
    // the TON and Stars values side-by-side, gated by which currency has data
    // (addOverview, info_channel_earn_list.cpp:682). Replaces the two separate
    // per-currency balance cards.
    final hasStars =
        available != 0 || current != 0 || overall != 0 || _transactions.isNotEmpty || _txLoadedOnce;
    Widget overviewValue(IconData icon, Color color, String amount, String usd) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 3),
            Text(amount, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textColor)),
          ]),
          if (usd.isNotEmpty)
            Text(usd, style: TextStyle(fontSize: 11, color: subTextColor.withValues(alpha: 0.7))),
        ],
      );
    }

    Widget overviewRow(String label, int tonVal, int starVal) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: subTextColor))),
          if (hasTon) ...[
            const SizedBox(width: 10),
            overviewValue(Icons.diamond, tonColor, _fmtTon(tonVal), _fmtUsdTon(tonVal, tonUsdRate)),
          ],
          if (hasStars) ...[
            const SizedBox(width: 18),
            overviewValue(Icons.star, starColor, '$starVal', _fmtUsd(starVal, usdRate)),
          ],
        ]),
      );
    }

    Widget combinedOverview() {
      if (!hasTon && !hasStars) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: Row(children: [
              Expanded(
                child: Text('Overview',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accentColor)),
              ),
              // Column headers indicate which currency each value belongs to.
              if (hasTon)
                const Icon(Icons.diamond, size: 14, color: tonColor),
              if (hasTon && hasStars) const SizedBox(width: 18),
              if (hasStars)
                const Icon(Icons.star, size: 14, color: starColor),
            ]),
          ),
          overviewRow('Available to withdraw', tonAvailable, available),
          Divider(height: 1, color: bgColor),
          overviewRow('Current balance', tonCurrent, current),
          Divider(height: 1, color: bgColor),
          overviewRow('Total lifetime revenue', tonOverall, overall),
          const SizedBox(height: 6),
        ]),
      );
    }

    List<Widget> tonSection() {
      if (!hasTon) return const [];
      return [
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
    } else if (!hasTon && available == 0 && current == 0 && overall == 0 &&
        _transactions.isEmpty && !_txLoadedOnce) {
      // Both currency & credits earn are empty — AyuGram shows Dialogs::SearchEmpty
      // (a lottie) here (info_channel_earn_list.cpp:357).
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.monetization_on_outlined, size: 56, color: subTextColor.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text('No earnings yet',
                  style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('Earnings from ads, paid reactions and paid content will appear here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: subTextColor, fontSize: 13)),
            ],
          ),
        ),
      );
    } else {
      body = Builder(builder: (_) {
        final _lvKids = <Widget>[
          // Combined TON+Stars overview (side-by-side, column-gated), then the
          // currency (TON) withdraw/charts/history, then the Stars equivalents.
          combinedOverview(),
          ...tonSection(),
          // Withdraw button + the optional "Buy Ads" button AyuGram renders
          // alongside it when buyAdsUrl is present (settings_credits_graphics.cpp:3346).
          // The withdraw button locks until nextWithdrawalAt with a live countdown
          // (info_channel_earn_list.cpp:940).
          if (withdrawalEnabled && available > 0)
            Builder(builder: (_) {
              final nextAt = (data['next_withdrawal_at'] as num?)?.toInt() ?? 0;
              final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
              final locked = nextAt > now;
              final buyAdsUrl = data['buy_ads_url'] as String? ?? '';
              String label;
              if (_withdrawing) {
                label = 'Processing…';
              } else if (locked) {
                final secs = nextAt - now;
                final h = secs ~/ 3600, m = (secs % 3600) ~/ 60, s = secs % 60;
                label = 'Available in ${h > 0 ? '${h}h ' : ''}${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
              } else {
                label = 'Withdraw';
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_withdrawing || locked) ? null : _withdraw,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: _withdrawing
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Icon(locked ? Icons.lock_clock : Icons.account_balance_wallet_outlined, size: 20),
                      label: Text(label),
                    ),
                  ),
                  if (buyAdsUrl.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => launchUrl(Uri.parse(buyAdsUrl), mode: LaunchMode.externalApplication),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        icon: const Icon(Icons.campaign_outlined, size: 20),
                        label: const Text('Buy Ads'),
                      ),
                    ),
                  ],
                ]),
              );
            }),
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
          // Transaction history (info_channel_earn_list.cpp:1288) with the
          // Full / Incoming / Outgoing filter tabs (AddCreditsHistoryList).
          if (_transactions.isNotEmpty || _loadingTx || _txLoadedOnce) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text('Transactions',
                  style: TextStyle(color: subTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            _buildTxFilterTabs(cardColor, textColor, subTextColor, accentColor),
            const SizedBox(height: 6),
            if (_transactions.isEmpty && _loadingTx)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else if (_transactions.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('No transactions.', style: TextStyle(color: subTextColor, fontSize: 13)),
              ),
            ..._transactions.map((tx) => _buildTransactionRow(tx, cardColor, textColor, subTextColor, starColor)),
            if (_txHasMore && _transactions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Center(
                  child: _loadingTx
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : TextButton(onPressed: _loadMoreTransactions, child: Text('Show more', style: TextStyle(color: accentColor))),
                ),
              ),
          ],
          // Restrict sponsored messages toggle (broadcast channels only,
          // info_channel_earn_list.cpp:1391).
          ..._buildSponsoredToggle(cardColor, textColor, subTextColor, accentColor),
        ];
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: _lvKids.length,
          itemBuilder: (_, _lvI) => _lvKids[_lvI],
        );
      });
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

/// StarRefLinkBox: shows the connected referral link, users count, recipient,
/// a copy action and the ToS (info_bot_starref_join_widget.cpp:519).
void showStarRefLinkBox(BuildContext context, Map<String, dynamic> bot) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
  final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
  final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
  final accentColor = PaletteProvider.of(context).windowBgActive;
  final url = bot['url'] as String? ?? bot['link'] as String? ?? '';
  final users = (bot['participants'] as num?)?.toInt() ?? (bot['users'] as num?)?.toInt() ?? 0;
  final botName = bot['bot_name'] as String? ?? bot['name'] as String? ?? 'Bot';
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: bgColor,
      title: Text('Affiliate Link', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Share this link to earn commission from $botName.',
              style: TextStyle(color: subTextColor, fontSize: 13)),
          const SizedBox(height: 12),
          if (url.isNotEmpty)
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: url));
                showTelegramToast(ctx, 'Link copied');
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(url.replaceFirst('https://', ''),
                    style: TextStyle(color: accentColor, fontSize: 14)),
              ),
            ),
          if (users > 0) ...[
            const SizedBox(height: 10),
            Text('$users users joined via this link', style: TextStyle(color: subTextColor, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        if (url.isNotEmpty)
          TextButton.icon(
            icon: Icon(Icons.copy, size: 16, color: accentColor),
            label: Text('Copy', style: TextStyle(color: accentColor)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              showTelegramToast(ctx, 'Link copied');
            },
          ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close', style: TextStyle(color: subTextColor))),
      ],
    ),
  );
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

// Suggested-list sort order (info_bot_starref_join_widget.cpp:385).
enum _StarRefSort { profitability, revenue, date }

class _StarRefJoinScreenState extends State<_StarRefJoinScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _connected = [];
  List<Map<String, dynamic>> _suggested = [];
  String _nextOffset = '';
  bool _loadingMore = false;
  final Set<String> _connecting = {};
  _StarRefSort _sort = _StarRefSort.profitability;

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
      final suggested = await engine.getSuggestedStarRefBots(widget.accountId, widget.chatId,
          orderByRevenue: _sort == _StarRefSort.revenue, orderByDate: _sort == _StarRefSort.date);
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
      final more = await engine.getSuggestedStarRefBots(widget.accountId, widget.chatId, offset: _nextOffset,
          orderByRevenue: _sort == _StarRefSort.revenue, orderByDate: _sort == _StarRefSort.date);
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

  // Tapping a suggested bot opens a confirmation (JoinStarRefBox) BEFORE
  // connecting — commission/duration, recipient, ToS (info_bot_starref_join_widget.cpp:545).
  Future<void> _confirmJoin(Map<String, dynamic> bot) async {
    final botName = bot['bot_name'] as String? ?? bot['name'] as String? ?? 'this bot';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Affiliate Program'),
        content: Text(
          'Join $botName\'s affiliate program and earn ${_commission(bot)} commission '
          '(${_duration(bot)}) for every user you refer.\n\n'
          'By joining, you agree to the Affiliate Program Terms.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Join')),
        ],
      ),
    );
    if (confirmed == true) _connect(bot);
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
      // AyuGram opens StarRefLinkBox (closing the join box) instead of writing to
      // the clipboard (info_bot_starref_common.cpp:666).
      if (mounted) showStarRefLinkBox(context, result.isNotEmpty ? result : bot);
    } catch (e) {
      if (mounted) {
        setState(() => _connecting.remove(botId));
        showTelegramToast(context, 'Failed: $e');
      }
    }
  }

  // Leave/revoke a connected affiliate program (EditConnectedStarRefBot
  // f_revoked) → move it back to suggested (info_bot_starref_join_widget.cpp:622).
  Future<void> _revoke(Map<String, dynamic> bot) async {
    final botId = bot['bot_id'] as String? ?? '';
    if (botId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Program'),
        content: const Text('Stop earning from this affiliate program? Your referral link will stop working.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave')),
        ],
      ),
    );
    if (confirmed != true) return;
    final engine = context.read<EngineService>();
    try {
      await engine.connectStarRefBot(widget.accountId, widget.chatId, botId,
          revoked: true, link: bot['url'] as String? ?? bot['link'] as String? ?? '');
      if (!mounted) return;
      setState(() {
        // Remove the revoked row from the Joined list (don't keep "· ended"),
        // and re-add it to the suggested list.
        _connected.removeWhere((b) => b['bot_id'] == botId);
        _suggested.insert(0, bot);
      });
    } catch (e) {
      if (mounted) showTelegramToast(context, 'Failed: $e');
    }
  }

  // FormatCommission: number(commission/10.) + '%' — drops trailing zeros so 50‰
  // renders "5%" not "5.0%" (info_bot_starref_common.cpp:222).
  static String formatCommission(int permille) {
    final v = permille / 10.0;
    final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
    return '$s%';
  }

  // FormatProgramDuration: localized lng_months / lng_years ("3 months", "1 year")
  // instead of raw "3mo"/"1y" (info_bot_starref_common.cpp:226).
  static String formatProgramDuration(int months) {
    if (months <= 0) return 'Lifetime';
    if (months % 12 == 0) {
      final y = months ~/ 12;
      return '$y ${y == 1 ? 'year' : 'years'}';
    }
    return '$months ${months == 1 ? 'month' : 'months'}';
  }

  String _commission(Map<String, dynamic> b) =>
      formatCommission((b['commission_permille'] as num?)?.toInt() ?? 0);

  String _duration(Map<String, dynamic> b) =>
      formatProgramDuration((b['duration_months'] as num?)?.toInt() ?? 0);

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
      body = Builder(builder: (_) {
        final _lvKids = <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Earn Telegram Stars by advertising other bots in your channel. '
              'Join a program below to get your referral link.',
              style: TextStyle(color: subTextColor, fontSize: 13),
            ),
          ),
          // Three info blocks (Reliable / Transparent / Simple) above the lists
          // (info_bot_starref_join_widget.cpp:715).
          if (_connected.isEmpty)
            ..._buildInfoBlocks(textColor, subTextColor, accentColor),
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
                onTap: () => showStarRefLinkBox(context, b),
                onRevoke: () => _revoke(b),
              ),
          ],
          if (_suggested.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('EXISTING PROGRAMS',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: accentColor)),
                  ),
                  // Sort picker (Profitability / Revenue / Date).
                  PopupMenuButton<_StarRefSort>(
                    initialValue: _sort,
                    onSelected: (s) {
                      setState(() => _sort = s);
                      _load();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: _StarRefSort.profitability, child: Text('Profitability')),
                      PopupMenuItem(value: _StarRefSort.revenue, child: Text('Revenue')),
                      PopupMenuItem(value: _StarRefSort.date, child: Text('Date')),
                    ],
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                        _sort == _StarRefSort.revenue
                            ? 'Revenue'
                            : _sort == _StarRefSort.date
                                ? 'Date'
                                : 'Profitability',
                        style: TextStyle(fontSize: 12, color: subTextColor),
                      ),
                      Icon(Icons.arrow_drop_down, size: 18, color: subTextColor),
                    ]),
                  ),
                ],
              ),
            ),
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
                onConnect: () => _confirmJoin(b),
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
        ];
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _lvKids.length,
          itemBuilder: (_, _lvI) => _lvKids[_lvI],
        );
      });
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

  // The three explanatory blocks shown above the lists
  // (info_bot_starref_join_widget.cpp:715).
  List<Widget> _buildInfoBlocks(Color textColor, Color subTextColor, Color accentColor) {
    Widget block(IconData icon, String title, String about) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accentColor, size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(about, style: TextStyle(color: subTextColor, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        );
    return [
      block(Icons.verified_user_outlined, 'Reliable',
          'Affiliate programs are run by Telegram and pay out automatically.'),
      block(Icons.visibility_outlined, 'Transparent',
          'Track exactly how many users you referred and how much you earned.'),
      block(Icons.bolt_outlined, 'Simple',
          'Share one link — earn a commission on every Star your referrals spend.'),
      const SizedBox(height: 8),
    ];
  }
}

class _ConnectedStarRefRow extends StatelessWidget {
  final Map<String, dynamic> bot;
  final Color cardColor, textColor, subTextColor, accentColor;
  final String commission, duration;
  final VoidCallback? onTap;
  final VoidCallback? onRevoke;
  const _ConnectedStarRefRow({
    required this.bot,
    required this.cardColor,
    required this.textColor,
    required this.subTextColor,
    required this.accentColor,
    required this.commission,
    required this.duration,
    this.onTap,
    this.onRevoke,
  });

  void _showMenu(BuildContext context, Offset pos) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final url = bot['url'] as String? ?? '';
    showMenu<String>(
      context: context,
      color: isDark ? const Color(0xFF1E2C3A) : Colors.white,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: const [
        PopupMenuItem(value: 'open', child: Text('Open Bot')),
        PopupMenuItem(value: 'copy', child: Text('Copy Link')),
        PopupMenuItem(value: 'revoke', child: Text('Leave Program')),
      ],
    ).then((v) {
      if (v == 'copy' && url.isNotEmpty) {
        Clipboard.setData(ClipboardData(text: url));
        showTelegramToast(context, 'Link copied');
      } else if (v == 'open') {
        final username = bot['bot_username'] as String? ?? '';
        if (username.isNotEmpty) launchUrl(Uri.parse('https://t.me/$username'));
      } else if (v == 'revoke') {
        onRevoke?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = (bot['bot_name'] as String?)?.trim();
    final username = bot['bot_username'] as String? ?? '';
    final avatarB64 = bot['avatar_b64'] as String? ?? '';
    final url = bot['url'] as String? ?? '';
    final revoked = bot['revoked'] == true;
    final display = (name != null && name.isNotEmpty) ? name : (username.isNotEmpty ? '@$username' : 'Bot');
    Widget inner = Container(
      margin: const EdgeInsets.fromLTRB(12, 3, 12, 3),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Real userpic with an overlaid chain-link badge for connected bots
              // (info_bot_starref_join_widget.cpp:199).
              Stack(clipBehavior: Clip.none, children: [
                avatarB64.isNotEmpty
                    ? CircleAvatar(radius: 18, backgroundImage: MemoryImage(base64Decode(avatarB64)))
                    : CircleAvatar(
                        radius: 18,
                        backgroundColor: accentColor,
                        child: Text(display.isNotEmpty ? display[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white, fontSize: 15))),
                Positioned(
                  right: -2, bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: cardColor, shape: BoxShape.circle),
                    child: Icon(Icons.link, size: 12, color: accentColor),
                  ),
                ),
              ]),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(display,
                        style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(duration, style: TextStyle(color: subTextColor, fontSize: 12)),
                  ],
                ),
              ),
              // Commission rendered as a styled rounded-rect badge
              // (paintStatusText, info_bot_starref_join_widget.cpp:170).
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: accentColor, borderRadius: BorderRadius.circular(8)),
                child: Text(commission,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
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
    // Tap opens StarRefLinkBox; right-click/long-press opens the context menu
    // (Open bot / Copy link / Leave) — info_bot_starref_join_widget.cpp:519/591.
    return GestureDetector(
      onTap: onTap,
      onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition),
      onLongPressStart: (d) => _showMenu(context, d.globalPosition),
      child: inner,
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
    final avatarB64 = bot['avatar_b64'] as String? ?? '';
    final display = (name != null && name.isNotEmpty) ? name : (username.isNotEmpty ? '@$username' : 'Bot');
    return InkWell(
      // Tap a suggested row opens JoinStarRefBox (confirmation) before connecting.
      onTap: onConnect,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 3, 12, 3),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            // Real peer userpic (info_bot_starref_join_widget.cpp:199).
            avatarB64.isNotEmpty
                ? CircleAvatar(radius: 18, backgroundImage: MemoryImage(base64Decode(avatarB64)))
                : CircleAvatar(
                    radius: 18,
                    backgroundColor: accentColor,
                    child: Text(display.isNotEmpty ? display[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white, fontSize: 15))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(display,
                      style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(duration, style: TextStyle(color: subTextColor, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Commission as a styled rounded-rect badge (paintStatusText).
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(commission,
                  style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.w700)),
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
      ),
    );
  }
}
