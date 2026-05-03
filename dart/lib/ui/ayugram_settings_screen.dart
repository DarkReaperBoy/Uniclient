import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'ayu_toggle.dart';
import 'confirm_box.dart';
import 'ghost_settings_page.dart';
import 'settings_style.dart';

class AyuGramSettingsScreen extends StatefulWidget {
  const AyuGramSettingsScreen({super.key});

  @override
  State<AyuGramSettingsScreen> createState() => _AyuGramSettingsScreenState();
}

class _AyuGramSettingsScreenState extends State<AyuGramSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dividerColor = isDark
        ? const Color(0xFF101921)
        : const Color(0xFFE0E0E0);
    final sectionLabelColor = isDark
        ? const Color(0xFF6AB2F2)
        : const Color(0xFF3390EC);
    final subtitleColor = isDark
        ? const Color(0xFF6D7F8F)
        : const Color(0xFF999999);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF17212B) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        title: const Text('AyuGram Preferences',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── AyuGram category: Ghost Mode + Spy + Other (§51.4) ──
          _NavRow(
            icon: Icons.visibility_off,
            iconBg: const Color(0xFF6B72D5),
            label: 'AyuGram',
            subtitle: appState.ghostModeEnabled ? 'Ghost Mode active' : null,
            isDark: isDark,
            onTap: () {
              Navigator.of(context).push(
                settingsPageRoute(
                  ChangeNotifierProvider.value(
                    value: appState,
                    child: const GhostSettingsPage(),
                  ),
                ),
              );
            },
          ),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          _ToggleRow(
            label: 'Show message seconds',
            subtitle: 'Display seconds in read timestamps (HH:mm:ss)',
            value: appState.showMessageSeconds,
            onChanged: (v) => appState.setShowMessageSeconds(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Context Menu Elements section (§54.7) ──
          _SectionLabel(label: 'Context Menu Elements', color: sectionLabelColor),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
            child: Text(
              'Extended menu items will be displayed if you hold CTRL or SHIFT while right-clicking on the message.',
              style: TextStyle(fontSize: 12, color: subtitleColor),
            ),
          ),
          _DropdownRow(
            label: 'Reactions Panel',
            value: appState.showReactionsPanelInContextMenu,
            items: const {0: 'Shown', 1: 'Hidden', 2: 'Extended Menu'},
            onChanged: (v) => appState.setShowReactionsPanelInContextMenu(v),
            isDark: isDark,
          ),
          _DropdownRow(
            label: 'Views Panel',
            value: appState.showViewsPanelInContextMenu,
            items: const {0: 'Shown', 1: 'Hidden', 2: 'Extended Menu'},
            onChanged: (v) => appState.setShowViewsPanelInContextMenu(v),
            isDark: isDark,
          ),
          _DropdownRow(
            label: 'Hide Message',
            value: appState.showHideMessageInContextMenu,
            items: const {0: 'Shown', 1: 'Hidden', 2: 'Extended Menu'},
            onChanged: (v) => appState.setShowHideMessageInContextMenu(v),
            isDark: isDark,
          ),
          _DropdownRow(
            label: 'User Messages',
            value: appState.showUserMessagesInContextMenu,
            items: const {0: 'Shown', 1: 'Hidden', 2: 'Extended Menu'},
            onChanged: (v) => appState.setShowUserMessagesInContextMenu(v),
            isDark: isDark,
          ),
          _DropdownRow(
            label: 'Message Details',
            value: appState.showMessageDetailsInContextMenu,
            items: const {0: 'Shown', 1: 'Hidden', 2: 'Extended Menu'},
            onChanged: (v) => appState.setShowMessageDetailsInContextMenu(v),
            isDark: isDark,
          ),
          _DropdownRow(
            label: 'Repeat Message',
            value: appState.showRepeatMessageInContextMenu,
            items: const {0: 'Shown', 1: 'Hidden', 2: 'Extended Menu'},
            onChanged: (v) => appState.setShowRepeatMessageInContextMenu(v),
            isDark: isDark,
          ),
          _DropdownRow(
            label: 'Add Filter',
            value: appState.showAddFilterInContextMenu,
            items: const {0: 'Shown', 1: 'Hidden', 2: 'Extended Menu'},
            onChanged: (v) => appState.setShowAddFilterInContextMenu(v),
            isDark: isDark,
          ),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Spy Essentials section (§52.1) ──
          _SectionLabel(label: 'Spy Essentials', color: sectionLabelColor),
          _ToggleRow(
            label: 'Save deleted messages',
            subtitle: 'Preserve messages that others delete',
            value: appState.saveDeletedMessages,
            onChanged: (v) => appState.setSaveDeletedMessages(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Save messages history',
            subtitle: 'Keep pre-edit text of edited messages',
            value: appState.saveMessagesHistory,
            onChanged: (v) => appState.setSaveMessagesHistory(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Save for bots',
            subtitle: 'Also save deleted/edited messages from bots',
            value: appState.saveForBots,
            onChanged: (v) => appState.setSaveForBots(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Semi-transparent deleted messages',
            subtitle: 'Reduce opacity for deleted messages (beta)',
            value: appState.semiTransparentDeleted,
            onChanged: (v) => appState.setSemiTransparentDeleted(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Replace marks with icons',
            subtitle: 'Use icons instead of text for deleted/edited status',
            value: appState.replaceMarksWithIcons,
            onChanged: (v) => appState.setReplaceMarksWithIcons(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _MarkButtonRow(
            label: 'Deleted mark',
            currentValue: appState.deletedMark,
            defaultValue: '\u{1F9F9}',
            onSaved: (v) => appState.setDeletedMark(v),
            isDark: isDark,
          ),
          _MarkButtonRow(
            label: 'Edited mark',
            currentValue: appState.editedMark,
            defaultValue: '',
            onSaved: (v) => appState.setEditedMark(v),
            isDark: isDark,
          ),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Messages section ──
          _SectionLabel(label: 'Messages', color: sectionLabelColor),
          _WideMultiplierSlider(
            value: appState.wideMultiplier,
            onChanged: (v) => appState.setWideMultiplier(v),
            isDark: isDark,
          ),
          _BubbleRadiusSection(
            value: appState.bubbleRadius,
            showTail: !appState.removeTail,
            simpleQuotes: appState.simpleQuotes,
            semiTransparentDeleted: appState.semiTransparentDeleted,
            replaceMarksWithIcons: appState.replaceMarksWithIcons,
            deletedMark: appState.deletedMark,
            editedMark: appState.editedMark,
            onChanged: (v) => appState.setBubbleRadius(v),
            isDark: isDark,
          ),
          _ToggleRow(
            label: 'Remove message tail',
            subtitle: 'Clean rounded rectangles without tail accent',
            value: appState.removeTail,
            onChanged: (v) => appState.setRemoveTail(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Simple quotes and replies',
            subtitle: 'Uniform reply bar style without colorful accents',
            value: appState.simpleQuotes,
            onChanged: (v) => appState.setSimpleQuotes(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Message Field Elements section (§54.9) ──
          _SectionLabel(label: 'Message Field Elements', color: sectionLabelColor),
          _ToggleRow(
            label: 'Attach',
            subtitle: 'Show paperclip button in compose area',
            value: appState.showAttachButton,
            onChanged: (v) => appState.setShowAttachButton(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Commands',
            subtitle: 'Show bot commands (/) button',
            value: appState.showCommandsButton,
            onChanged: (v) => appState.setShowCommandsButton(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'TTL',
            subtitle: 'Show auto-delete timer button',
            value: appState.showAutoDeleteButton,
            onChanged: (v) => appState.setShowAutoDeleteButton(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Emoji',
            subtitle: 'Show emoji button in compose area',
            value: appState.showEmojiButton,
            onChanged: (v) => appState.setShowEmojiButton(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Voice',
            subtitle: 'Show microphone/voice button',
            value: appState.showMicrophoneButton,
            onChanged: (v) => appState.setShowMicrophoneButton(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Gift',
            subtitle: 'Show gift button in DMs',
            value: appState.showGiftButton,
            onChanged: (v) => appState.setShowGiftButton(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'AI Editor',
            subtitle: 'Show AI editor button in compose area',
            value: appState.showAiEditorButton,
            onChanged: (v) => appState.setShowAiEditorButton(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Message Field Popups section (§54.9) ──
          _SectionLabel(label: 'Message Field Popups', color: sectionLabelColor),
          _ToggleRow(
            label: 'Attach popup',
            subtitle: 'Show file/poll picker when pressing attach',
            value: appState.showAttachPopup,
            onChanged: (v) => appState.setShowAttachPopup(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Emoji popup',
            subtitle: 'Show emoji/sticker panel when pressing emoji',
            value: appState.showEmojiPopup,
            onChanged: (v) => appState.setShowEmojiPopup(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Stickers & Emoji section (§54.11) ──
          _SectionLabel(label: 'Stickers & Emoji', color: sectionLabelColor),
          _ToggleRow(
            label: 'Show only added emojis/stickers',
            subtitle: 'Filter picker to only show packs you\'ve added',
            value: appState.showOnlyAddedEmojisAndStickers,
            onChanged: (v) => appState.setShowOnlyAddedEmojisAndStickers(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _CollapsibleToggle(
            label: 'Hide Reactions',
            isExpanded: !appState.showChannelReactions ||
                !appState.showGroupReactions ||
                !appState.showPrivateChatReactions,
            isDark: isDark,
            useMaterial: appState.materialSwitches,
            children: [
              _NestedCheckbox(
                label: 'Hide in channels',
                value: !appState.showChannelReactions,
                onChanged: (v) => appState.setShowChannelReactions(!v),
                isDark: isDark,
              ),
              _NestedCheckbox(
                label: 'Hide in groups',
                value: !appState.showGroupReactions,
                onChanged: (v) => appState.setShowGroupReactions(!v),
                isDark: isDark,
              ),
              _NestedCheckbox(
                label: 'Hide in private chats',
                value: !appState.showPrivateChatReactions,
                onChanged: (v) => appState.setShowPrivateChatReactions(!v),
                isDark: isDark,
              ),
            ],
          ),
          _SliderRow(
            label: 'Recent Stickers Count',
            value: appState.recentStickersCount,
            min: 0,
            max: 200,
            divisions: 200,
            valueLabel: '${appState.recentStickersCount}',
            onChanged: (v) => appState.setRecentStickersCount(v.round()),
            isDark: isDark,
          ),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Channels section (§54.11) ──
          _SectionLabel(label: 'Channels', color: sectionLabelColor),
          _DropdownRow(
            label: 'Channel Bottom Button',
            value: appState.channelBottomButton,
            items: const {0: 'Hidden', 1: 'Mute/Unmute', 2: 'Discuss (fallback)'},
            onChanged: (v) => appState.setChannelBottomButton(v),
            isDark: isDark,
          ),
          _ToggleRow(
            label: 'Quick Admin Shortcuts',
            subtitle: 'Enable quick admin action shortcuts',
            value: appState.quickAdminShortcuts,
            onChanged: (v) => appState.setQuickAdminShortcuts(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Message Shot',
            subtitle: 'Share styled message screenshots',
            value: appState.showMessageShot,
            onChanged: (v) => appState.setShowMessageShot(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Hide side "Share" button',
            subtitle: 'Hide the circular forward button on messages',
            value: appState.hideFastShare,
            onChanged: (v) => appState.setHideFastShare(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Appearance section ──
          _SectionLabel(label: 'Appearance', color: sectionLabelColor),
          _ToggleRow(
            label: 'Material Design switches',
            subtitle: 'Use Material-style toggle switches throughout',
            value: appState.materialSwitches,
            onChanged: (v) => appState.setMaterialSwitches(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _AvatarCornersSection(
            corners: appState.avatarCorners,
            singleCornerRadius: appState.singleCornerRadius,
            onCornersChanged: (v) => appState.setAvatarCorners(v),
            onSingleCornerRadiusChanged: (v) => appState.setSingleCornerRadius(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Disable custom backgrounds',
            subtitle: 'Force global wallpaper on all chats',
            value: appState.disableCustomBackgrounds,
            onChanged: (v) => appState.setDisableCustomBackgrounds(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Hide premium statuses',
            subtitle: 'Hide emoji status badges next to usernames',
            value: appState.hidePremiumStatuses,
            onChanged: (v) => appState.setHidePremiumStatuses(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _MonoFontRow(
            currentFont: appState.monoFont,
            onChanged: (v) => appState.setMonoFont(v),
            isDark: isDark,
          ),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Chat Folders section (§54.10) ──
          _SectionLabel(label: 'Chat Folders', color: sectionLabelColor),
          _ToggleRow(
            label: 'Hide notification counters',
            subtitle: 'Hide unread count badges on folder tabs',
            value: appState.hideNotificationCounters,
            onChanged: (v) => appState.setHideNotificationCounters(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Hide "All Chats" tab',
            subtitle: 'Remove the All Chats folder tab from the folder bar',
            value: appState.hideAllChatsFolder,
            onChanged: (v) => appState.setHideAllChatsFolder(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── App Icon section (§54.10) ──
          _SectionLabel(label: 'App Icon', color: sectionLabelColor),
          _AppIconPicker(
            selectedIcon: appState.appIcon,
            onChanged: (v) => appState.setAppIcon(v),
            isDark: isDark,
          ),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Drawer Elements section (§54.8) ──
          _SectionLabel(label: 'Drawer Elements', color: sectionLabelColor),
          _ToggleRow(
            label: 'My Profile',
            subtitle: 'Show My Profile in drawer',
            value: appState.showMyProfileInDrawer,
            onChanged: (v) => appState.setShowMyProfileInDrawer(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          if (appState.menuBots.isNotEmpty)
          _ToggleRow(
            label: 'Bots',
            subtitle: 'Show menu bots in drawer',
            value: appState.showBotsInDrawer,
            onChanged: (v) => appState.setShowBotsInDrawer(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'New Group',
            subtitle: 'Show New Group in drawer',
            value: appState.showNewGroupInDrawer,
            onChanged: (v) => appState.setShowNewGroupInDrawer(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'New Channel',
            subtitle: 'Show New Channel in drawer',
            value: appState.showNewChannelInDrawer,
            onChanged: (v) => appState.setShowNewChannelInDrawer(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Contacts',
            subtitle: 'Show Contacts in drawer',
            value: appState.showContactsInDrawer,
            onChanged: (v) => appState.setShowContactsInDrawer(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Calls',
            subtitle: 'Show Calls in drawer',
            value: appState.showCallsInDrawer,
            onChanged: (v) => appState.setShowCallsInDrawer(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Saved Messages',
            subtitle: 'Show Saved Messages in drawer',
            value: appState.showSavedMessagesInDrawer,
            onChanged: (v) => appState.setShowSavedMessagesInDrawer(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Night Mode',
            subtitle: 'Show Night Mode toggle in drawer',
            value: appState.showDrawerThemeToggle,
            onChanged: (v) => appState.setShowDrawerThemeToggle(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Ghost Mode',
            subtitle: 'Show Ghost Mode toggle in drawer',
            value: appState.showGhostToggleInDrawer,
            onChanged: (v) => appState.setShowGhostToggleInDrawer(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Read Receipts (LRead)',
            subtitle: 'Show Read Receipts toggle in drawer',
            value: appState.showLReadToggleInDrawer,
            onChanged: (v) => appState.setShowLReadToggleInDrawer(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Story Reads (SRead)',
            subtitle: 'Show Story Reads toggle in drawer',
            value: appState.showSReadToggleInDrawer,
            onChanged: (v) => appState.setShowSReadToggleInDrawer(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Streamer Mode',
            subtitle: 'Show Streamer Mode toggle in drawer',
            value: appState.showStreamerToggleInDrawer,
            onChanged: (v) => appState.setShowStreamerToggleInDrawer(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Tray Elements section (§54.8) ──
          _SectionLabel(label: 'Tray Elements', color: sectionLabelColor),
          _ToggleRow(
            label: 'Ghost Mode',
            subtitle: 'Show Ghost Mode toggle in system tray menu',
            value: appState.showGhostToggleInTray,
            onChanged: (v) => appState.setShowGhostToggleInTray(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Streamer Mode',
            subtitle: 'Show Streamer Mode toggle in system tray menu',
            value: appState.showStreamerToggleInTray,
            onChanged: (v) => appState.setShowStreamerToggleInTray(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
            child: Text(
              'These settings are specific to AyuGram/UniClient and may '
              'differ from the standard Telegram Desktop experience.',
              style: TextStyle(fontSize: 12, color: subtitleColor),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _WideMultiplierSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final bool isDark;

  const _WideMultiplierSlider({
    required this.value,
    required this.onChanged,
    required this.isDark,
  });

  @override
  State<_WideMultiplierSlider> createState() => _WideMultiplierSliderState();
}

class _WideMultiplierSliderState extends State<_WideMultiplierSlider> {
  late double _localValue;
  double _committedValue = -1;

  @override
  void initState() {
    super.initState();
    _localValue = widget.value;
    _committedValue = widget.value;
  }

  @override
  void didUpdateWidget(_WideMultiplierSlider old) {
    super.didUpdateWidget(old);
    if ((old.value - widget.value).abs() > 0.001) {
      _localValue = widget.value;
      _committedValue = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = const Color(0xFF40A7E3);
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final subtitleColor = widget.isDark
        ? const Color(0xFF6D7F8F)
        : const Color(0xFF999999);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Wide Messages Multiplier',
                    style: TextStyle(fontSize: 14, color: textColor)),
              ),
              Text(_localValue.toStringAsFixed(2),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF40A7E3))),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accentColor,
              inactiveTrackColor: widget.isDark
                  ? const Color(0xFF2B3C4C)
                  : const Color(0xFFD5D5D5),
              thumbColor: accentColor,
              overlayColor: const Color(0x2940A7E3),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5),
            ),
            child: Slider(
              value: _localValue,
              min: 1.0,
              max: 4.0,
              divisions: 60,
              onChanged: (v) {
                setState(() => _localValue = v);
              },
              onChangeEnd: (v) {
                final snapped = (v * 20).round() / 20.0;
                if ((snapped - _committedValue).abs() < 0.001) return;
                showConfirmBox(
                  context,
                  title: 'Restart Required',
                  text: 'Some settings will be applied after restarting.',
                  confirmText: 'Apply',
                  cancelText: 'Cancel',
                  onConfirm: () {
                    _committedValue = snapped;
                    widget.onChanged(snapped);
                  },
                  onCancel: () {
                    setState(() => _localValue = _committedValue);
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Change message width for better display on wide monitors.',
              style: TextStyle(fontSize: 12, color: subtitleColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color color;
  const _SectionLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
      child: Text(label,
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w500, color: color)),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isDark;
  final bool useMaterial;

  const _ToggleRow({
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
    required this.isDark,
    this.useMaterial = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!,
                          style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? const Color(0xFF6D7F8F)
                                  : const Color(0xFF999999))),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AyuToggle(
              value: value,
              onChanged: onChanged,
              isMaterial: useMaterial,
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final int value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;
  final bool isDark;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87)),
              ),
              Text(valueLabel,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF40A7E3))),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFF40A7E3),
              inactiveTrackColor: isDark
                  ? const Color(0xFF2B3C4C)
                  : const Color(0xFFD5D5D5),
              thumbColor: const Color(0xFF40A7E3),
              overlayColor: const Color(0x2940A7E3),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5),
            ),
            child: Slider(
              value: value.toDouble(),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _BubbleRadiusSection extends StatefulWidget {
  final int value;
  final bool showTail;
  final bool simpleQuotes;
  final bool semiTransparentDeleted;
  final bool replaceMarksWithIcons;
  final String deletedMark;
  final String editedMark;
  final ValueChanged<int> onChanged;
  final bool isDark;

  const _BubbleRadiusSection({
    required this.value,
    required this.showTail,
    required this.simpleQuotes,
    required this.semiTransparentDeleted,
    required this.replaceMarksWithIcons,
    required this.deletedMark,
    required this.editedMark,
    required this.onChanged,
    required this.isDark,
  });

  @override
  State<_BubbleRadiusSection> createState() => _BubbleRadiusSectionState();
}

class _BubbleRadiusSectionState extends State<_BubbleRadiusSection> {
  late int _localValue;
  late int _committedValue;

  @override
  void initState() {
    super.initState();
    _localValue = widget.value;
    _committedValue = widget.value;
  }

  @override
  void didUpdateWidget(_BubbleRadiusSection old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _localValue = widget.value;
      _committedValue = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final radiusLarge = _localValue.toDouble();
    final radiusSmall = widget.showTail
        ? (radiusLarge * 6 / 16).clamp(0.0, 6.0)
        : radiusLarge;
    final subtitleColor = widget.isDark
        ? const Color(0xFF6D7F8F)
        : const Color(0xFF999999);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Slider
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Message Bubble Radius',
                        style: TextStyle(
                            fontSize: 14,
                            color: widget.isDark ? Colors.white : Colors.black87)),
                  ),
                  Text('$_localValue',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF40A7E3))),
                ],
              ),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: const Color(0xFF40A7E3),
                  inactiveTrackColor: widget.isDark
                      ? const Color(0xFF2B3C4C)
                      : const Color(0xFFD5D5D5),
                  thumbColor: const Color(0xFF40A7E3),
                  overlayColor: const Color(0x2940A7E3),
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5),
                ),
                child: Slider(
                  value: _localValue.toDouble(),
                  min: 0,
                  max: 16,
                  divisions: 16,
                  onChanged: (v) {
                    setState(() => _localValue = v.round());
                  },
                  onChangeEnd: (v) {
                    final newVal = v.round();
                    if (newVal == _committedValue) return;
                    showConfirmBox(
                      context,
                      title: 'Restart Required',
                      text: 'Bubble radius will be applied after restarting.',
                      confirmText: 'Apply',
                      cancelText: 'Cancel',
                      onConfirm: () {
                        _committedValue = newVal;
                        widget.onChanged(newVal);
                      },
                      onCancel: () {
                        setState(() => _localValue = _committedValue);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        // Live MessagePreview — spec §54.4
        _MessagePreview(
          radiusLarge: radiusLarge,
          radiusSmall: radiusSmall,
          showTail: widget.showTail,
          simpleQuotes: widget.simpleQuotes,
          semiTransparentDeleted: widget.semiTransparentDeleted,
          replaceMarksWithIcons: widget.replaceMarksWithIcons,
          deletedMark: widget.deletedMark,
          editedMark: widget.editedMark,
          isDark: widget.isDark,
        ),
      ],
    );
  }
}

class _MessagePreview extends StatelessWidget {
  final double radiusLarge;
  final double radiusSmall;
  final bool showTail;
  final bool simpleQuotes;
  final bool semiTransparentDeleted;
  final bool replaceMarksWithIcons;
  final String deletedMark;
  final String editedMark;
  final bool isDark;

  const _MessagePreview({
    required this.radiusLarge,
    required this.radiusSmall,
    required this.showTail,
    required this.simpleQuotes,
    required this.semiTransparentDeleted,
    required this.replaceMarksWithIcons,
    required this.deletedMark,
    required this.editedMark,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final inBg = isDark ? const Color(0xFF182533) : const Color(0xFFFFFFFF);
    final outBg = isDark ? const Color(0xFF2B5278) : const Color(0xFFEFFEDE);
    final textColor = isDark ? Colors.white.withValues(alpha: 0.87) : Colors.black87;
    final metaColor = isDark ? const Color(0xFF6D8DA0) : const Color(0xFF5E9E5E);
    final quoteBarColor = simpleQuotes
        ? (isDark ? const Color(0xFF65B9F4) : const Color(0xFF168ACD))
        : const Color(0xFF4FAD2D);
    final quoteNameColor = simpleQuotes
        ? (isDark ? const Color(0xFF65B9F4) : const Color(0xFF168ACD))
        : const Color(0xFF4FAD2D);
    final deletedOpacity = semiTransparentDeleted ? 0.7 : 1.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0E1621) : const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Incoming message: "Update wehn?"
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 240),
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: inBg,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(radiusLarge),
                    topRight: Radius.circular(radiusLarge),
                    bottomLeft: Radius.circular(radiusSmall),
                    bottomRight: Radius.circular(radiusLarge),
                  ),
                  boxShadow: [
                    if (!isDark)
                      const BoxShadow(
                        color: Color(0x18000000),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('User',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: quoteNameColor)),
                    const SizedBox(height: 2),
                    Text('Update wehn?',
                        style: TextStyle(fontSize: 13, color: textColor)),
                    const SizedBox(height: 2),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('12:00',
                          style: TextStyle(fontSize: 11, color: metaColor)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Outgoing message with reply quote: "You need to touch some grass."
            Align(
              alignment: Alignment.centerRight,
              child: Opacity(
                opacity: deletedOpacity,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 260),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: outBg,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(radiusLarge),
                      topRight: Radius.circular(radiusLarge),
                      bottomLeft: Radius.circular(radiusLarge),
                      bottomRight: Radius.circular(radiusSmall),
                    ),
                    boxShadow: [
                      if (!isDark)
                        const BoxShadow(
                          color: Color(0x18000000),
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Reply quote block
                      Container(
                        padding: const EdgeInsets.only(left: 8, top: 3, bottom: 3, right: 6),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(width: 2, color: quoteBarColor),
                          ),
                          color: simpleQuotes
                              ? Colors.transparent
                              : quoteBarColor.withValues(alpha: 0.1),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(4),
                            bottomRight: Radius.circular(4),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('User',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: quoteNameColor)),
                            Text('Update wehn?',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: textColor.withValues(alpha: 0.7))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('You need to touch some grass.',
                          style: TextStyle(fontSize: 13, color: textColor)),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Spacer(),
                          ..._buildMarks(textColor, metaColor),
                          Text('12:01',
                              style: TextStyle(fontSize: 11, color: metaColor)),
                          const SizedBox(width: 3),
                          Icon(Icons.done_all, size: 14, color: metaColor),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMarks(Color textColor, Color metaColor) {
    final marks = <Widget>[];
    if (replaceMarksWithIcons) {
      marks.add(Padding(
        padding: const EdgeInsets.only(right: 3),
        child: Icon(Icons.delete_outline, size: 12, color: metaColor),
      ));
      marks.add(Padding(
        padding: const EdgeInsets.only(right: 3),
        child: Icon(Icons.edit, size: 12, color: metaColor),
      ));
    } else {
      if (deletedMark.isNotEmpty) {
        marks.add(Padding(
          padding: const EdgeInsets.only(right: 3),
          child: Text(deletedMark, style: TextStyle(fontSize: 11, color: metaColor)),
        ));
      }
      if (editedMark.isNotEmpty) {
        marks.add(Padding(
          padding: const EdgeInsets.only(right: 3),
          child: Text(editedMark, style: TextStyle(fontSize: 11, color: metaColor)),
        ));
      } else {
        marks.add(Padding(
          padding: const EdgeInsets.only(right: 3),
          child: Text('edited', style: TextStyle(fontSize: 11, color: metaColor)),
        ));
      }
    }
    return marks;
  }
}

class _AvatarCornersSection extends StatelessWidget {
  final int corners;
  final bool singleCornerRadius;
  final ValueChanged<int> onCornersChanged;
  final ValueChanged<bool> onSingleCornerRadiusChanged;
  final bool isDark;
  final bool useMaterial;

  const _AvatarCornersSection({
    required this.corners,
    required this.singleCornerRadius,
    required this.onCornersChanged,
    required this.onSingleCornerRadiusChanged,
    required this.isDark,
    required this.useMaterial,
  });

  static const _kMax = 23;

  String get _badgeText {
    if (corners == 0) return 'SQUARE';
    if (corners >= _kMax) return 'CIRCLE';
    return '$corners';
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
          child: Row(
            children: [
              Text('Avatar Corners',
                  style: TextStyle(fontSize: 14, color: textColor)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(_badgeText,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ),
            ],
          ),
        ),
        _AvatarCornersPreview(corners: corners, isDark: isDark),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accentColor,
              inactiveTrackColor: isDark
                  ? const Color(0xFF2B3C4C)
                  : const Color(0xFFD5D5D5),
              thumbColor: accentColor,
              overlayColor: const Color(0x2940A7E3),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5),
            ),
            child: Slider(
              value: corners.toDouble(),
              min: 0,
              max: _kMax.toDouble(),
              divisions: _kMax,
              onChanged: (v) => onCornersChanged(v.round()),
            ),
          ),
        ),
        _ToggleRow(
          label: 'Single corner radius',
          subtitle: 'Forums will have the same avatar shape as chats',
          value: singleCornerRadius,
          onChanged: onSingleCornerRadiusChanged,
          isDark: isDark,
          useMaterial: useMaterial,
        ),
      ],
    );
  }
}

class _AvatarCornersPreview extends StatelessWidget {
  final int corners;
  final bool isDark;

  const _AvatarCornersPreview({required this.corners, required this.isDark});

  @override
  Widget build(BuildContext context) {
    const photoSize = 46.0;
    final avatarRadius = photoSize / 2 * (corners / 23.0);
    final bgColor = isDark ? const Color(0xFF182533) : const Color(0xFFF1F1F1);
    final nameColor = isDark ? Colors.white : Colors.black87;
    final previewColor = isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    const rowHeight = 62.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
      child: Container(
        height: rowHeight,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Container(
              width: photoSize,
              height: photoSize,
              decoration: BoxDecoration(
                color: const Color(0xFF8544D6),
                borderRadius: BorderRadius.circular(avatarRadius),
              ),
              child: Center(
                child: Text('A',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.9))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('AyuGram Releases',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: nameColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text('Preview of avatar corners',
                      style: TextStyle(fontSize: 13, color: previewColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String label;
  final String? subtitle;
  final bool isDark;
  final VoidCallback onTap;

  const _NavRow({
    required this.icon,
    required this.iconBg,
    required this.label,
    this.subtitle,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: SettingsStyle.iconRowPadding,
        child: Row(
          children: [
            Container(
              width: SettingsStyle.iconSize,
              height: SettingsStyle.iconSize,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(SettingsStyle.iconRadius),
              ),
              child: Icon(icon, color: Colors.white, size: SettingsStyle.iconInner),
            ),
            const SizedBox(width: SettingsStyle.iconGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: SettingsStyle.buttonFontSize,
                          color: textColor)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!,
                          style: TextStyle(
                              fontSize: 12,
                              color: subtextColor)),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 20,
                color: isDark ? const Color(0xFF5A6A78) : const Color(0xFFCBCBCB)),
          ],
        ),
      ),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  final String label;
  final int value;
  final Map<int, String> items;
  final ValueChanged<int> onChanged;
  final bool isDark;

  const _DropdownRow({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87)),
          ),
          const SizedBox(width: 12),
          DropdownButton<int>(
            value: value,
            underline: const SizedBox.shrink(),
            dropdownColor: isDark ? const Color(0xFF1B2836) : Colors.white,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC),
            ),
            items: items.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

class _MarkButtonRow extends StatelessWidget {
  final String label;
  final String currentValue;
  final String defaultValue;
  final ValueChanged<String> onSaved;
  final bool isDark;

  const _MarkButtonRow({
    required this.label,
    required this.currentValue,
    required this.defaultValue,
    required this.onSaved,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = currentValue.isEmpty ? '(default)' : currentValue;
    return InkWell(
      onTap: () => _showEditMarkBox(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87)),
            ),
            Text(displayValue,
                style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? const Color(0xFF6AB2F2)
                        : const Color(0xFF3390EC))),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                size: 20,
                color: isDark
                    ? const Color(0xFF5A6A78)
                    : const Color(0xFFCBCBCB)),
          ],
        ),
      ),
    );
  }

  void _showEditMarkBox(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _EditMarkBox(
        title: label,
        currentValue: currentValue,
        defaultValue: defaultValue,
        onSaved: onSaved,
      ),
    );
  }
}

class _EditMarkBox extends StatefulWidget {
  final String title;
  final String currentValue;
  final String defaultValue;
  final ValueChanged<String> onSaved;

  const _EditMarkBox({
    required this.title,
    required this.currentValue,
    required this.defaultValue,
    required this.onSaved,
  });

  @override
  State<_EditMarkBox> createState() => _EditMarkBoxState();
}

class _EditMarkBoxState extends State<_EditMarkBox> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1B2836) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final accentColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: 320,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor)),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                style: TextStyle(fontSize: 14, color: textColor),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                        color: isDark
                            ? const Color(0xFF3B4A59)
                            : const Color(0xFFDDDDDD)),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: accentColor, width: 2),
                  ),
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: _resetToDefault,
                    child: Text('Reset to default',
                        style: TextStyle(fontSize: 13, color: accentColor)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel',
                        style: TextStyle(fontSize: 13, color: accentColor)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _save,
                    child: Text('Save',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: accentColor)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    widget.onSaved(_controller.text);
    Navigator.of(context).pop();
  }

  void _resetToDefault() {
    _controller.text = widget.defaultValue;
  }
}

class _MonoFontRow extends StatelessWidget {
  final String currentFont;
  final ValueChanged<String> onChanged;
  final bool isDark;

  const _MonoFontRow({
    required this.currentFont,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = currentFont.isEmpty ? 'Default' : currentFont;
    return InkWell(
      onTap: () => _showFontSelectorBox(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Monospace font',
                      style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87)),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Font for code and pre blocks',
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? const Color(0xFF6D7F8F)
                              : const Color(0xFF999999)),
                    ),
                  ),
                ],
              ),
            ),
            Text(displayValue,
                style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? const Color(0xFF6AB2F2)
                        : const Color(0xFF3390EC))),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                size: 20,
                color: isDark
                    ? const Color(0xFF5A6A78)
                    : const Color(0xFFCBCBCB)),
          ],
        ),
      ),
    );
  }

  void _showFontSelectorBox(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _FontSelectorBox(
        currentFont: currentFont,
        onSaved: onChanged,
      ),
    );
  }
}

class _FontSelectorBox extends StatefulWidget {
  final String currentFont;
  final ValueChanged<String> onSaved;

  const _FontSelectorBox({
    required this.currentFont,
    required this.onSaved,
  });

  @override
  State<_FontSelectorBox> createState() => _FontSelectorBoxState();
}

class _FontSelectorBoxState extends State<_FontSelectorBox> {
  late final TextEditingController _controller;

  static const _presets = [
    '',
    'Cascadia Mono',
    'JetBrains Mono',
    'Fira Code',
    'Source Code Pro',
    'Inconsolata',
    'Ubuntu Mono',
    'Hack',
    'Roboto Mono',
    'IBM Plex Mono',
    'Cousine',
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentFont);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1B2836) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final accentColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    final subtitleColor =
        isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: 320,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Monospace Font',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor)),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                style: TextStyle(fontSize: 14, color: textColor),
                decoration: InputDecoration(
                  hintText: 'Cascadia Mono',
                  hintStyle: TextStyle(fontSize: 14, color: subtitleColor),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                        color: isDark
                            ? const Color(0xFF3B4A59)
                            : const Color(0xFFDDDDDD)),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: accentColor, width: 2),
                  ),
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _presets.length,
                  itemBuilder: (ctx, i) {
                    final font = _presets[i];
                    final isSelected = _controller.text == font;
                    final label = font.isEmpty ? 'Default (Cascadia Mono)' : font;
                    return InkWell(
                      onTap: () {
                        setState(() => _controller.text = font);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontFamily: font.isEmpty ? 'monospace' : font,
                                    color: isSelected ? accentColor : textColor,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  )),
                            ),
                            if (isSelected)
                              Icon(Icons.check, size: 18, color: accentColor),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel',
                        style: TextStyle(fontSize: 13, color: accentColor)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _save,
                    child: Text('Save',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: accentColor)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    widget.onSaved(_controller.text);
    Navigator.of(context).pop();
  }
}

class _AppIconPicker extends StatelessWidget {
  final String selectedIcon;
  final ValueChanged<String> onChanged;
  final bool isDark;

  const _AppIconPicker({
    required this.selectedIcon,
    required this.onChanged,
    required this.isDark,
  });

  static const _icons = [
    'default', 'alt', 'discord', 'spotify', 'extera', 'nothing',
    'bard', 'yaplus', 'win95', 'chibi', 'chibi2', 'extera2',
  ];

  static const _iconColors = [
    Color(0xFF40A7E3), Color(0xFF5288C1), Color(0xFF5865F2), Color(0xFF1DB954),
    Color(0xFF6B72D5), Color(0xFF808080), Color(0xFFE67E22), Color(0xFFCC3333),
    Color(0xFF008080), Color(0xFFFF69B4), Color(0xFFDA70D6), Color(0xFF4169E1),
  ];

  @override
  Widget build(BuildContext context) {
    final selected = selectedIcon.isEmpty ? 'default' : selectedIcon;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: _icons.length,
        itemBuilder: (ctx, i) {
          final name = _icons[i];
          final isSelected = name == selected;
          final color = _iconColors[i % _iconColors.length];
          return GestureDetector(
            onTap: () => onChanged(name == 'default' ? '' : name),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: isSelected
                    ? Border.all(
                        color: isDark
                            ? const Color(0xFF6AB2F2)
                            : const Color(0xFF3390EC),
                        width: 2,
                      )
                    : null,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    name == 'default' ? 'U' : name[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CollapsibleToggle extends StatefulWidget {
  final String label;
  final bool isExpanded;
  final bool isDark;
  final bool useMaterial;
  final List<Widget> children;

  const _CollapsibleToggle({
    required this.label,
    required this.isExpanded,
    required this.isDark,
    required this.children,
    this.useMaterial = false,
  });

  @override
  State<_CollapsibleToggle> createState() => _CollapsibleToggleState();
}

class _CollapsibleToggleState extends State<_CollapsibleToggle> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = widget.isExpanded;
  }

  @override
  void didUpdateWidget(_CollapsibleToggle old) {
    super.didUpdateWidget(old);
    if (old.isExpanded != widget.isExpanded) {
      _open = widget.isExpanded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final anyChecked = widget.isExpanded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(widget.label,
                          style: TextStyle(
                              fontSize: 14,
                              color: widget.isDark ? Colors.white : Colors.black87)),
                      if (anyChecked) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.isDark
                                ? const Color(0xFF6AB2F2)
                                : const Color(0xFF3390EC),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: widget.isDark
                      ? const Color(0xFF6AB2F2)
                      : const Color(0xFF3390EC),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: _open
              ? Column(children: widget.children)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _NestedCheckbox extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isDark;

  const _NestedCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.only(left: 44, right: 22, top: 6, bottom: 6),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: isDark
                    ? const Color(0xFF6AB2F2)
                    : const Color(0xFF3390EC),
                side: BorderSide(
                  color: isDark
                      ? const Color(0xFF5A6A78)
                      : const Color(0xFFCBCBCB),
                  width: 2,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white : Colors.black87)),
          ],
        ),
      ),
    );
  }
}
