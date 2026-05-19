import 'package:flutter/material.dart';
import '../theme/telegram_palette.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'ayu_section_builder.dart';
import 'ayu_toggle.dart';
import 'confirm_box.dart';

class AyuChatsPage extends StatelessWidget {
  const AyuChatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final b = AyuSectionBuilder(
        isDark: isDark, useMaterial: appState.materialSwitches);

    b.addSkip();

    // Stickers & Emoji (§54.11)
    b.addSubsectionTitle('Stickers & Emoji');
    b.addSettingToggle(
      label: 'Show only added emojis/stickers',
      subtitle: 'Filter picker to only show packs you\'ve added',
      value: appState.showOnlyAddedEmojisAndStickers,
      onChanged: (v) => appState.setShowOnlyAddedEmojisAndStickers(v),
    );
    b.addCollapsibleToggle(
      label: 'Hide Reactions',
      isExpanded: !appState.showChannelReactions ||
          !appState.showGroupReactions ||
          !appState.showPrivateChatReactions,
      onMasterToggle: (hideAll) {
        appState.setShowChannelReactions(!hideAll);
        appState.setShowGroupReactions(!hideAll);
        appState.setShowPrivateChatReactions(!hideAll);
      },
      children: [
        AyuNestedCheckboxItem(
          label: 'Hide in channels',
          value: !appState.showChannelReactions,
          onChanged: (v) => appState.setShowChannelReactions(!v),
        ),
        AyuNestedCheckboxItem(
          label: 'Hide in groups',
          value: !appState.showGroupReactions,
          onChanged: (v) => appState.setShowGroupReactions(!v),
        ),
        AyuNestedCheckboxItem(
          label: 'Hide in private chats',
          value: !appState.showPrivateChatReactions,
          onChanged: (v) => appState.setShowPrivateChatReactions(!v),
        ),
      ],
    );
    b.addSectionDivider();
    b.addSlider(
      label: 'Recent Stickers Count',
      steps: 201,
      current: appState.recentStickersCount,
      indexToValue: (i) => i,
      formatLabel: (v) => '$v',
      onChanged: (v) => appState.setRecentStickersCount(v),
    );

    b.addSectionDivider();

    // Channels (§54.11)
    b.addSubsectionTitle('Channels');
    b.addChooseButton(
      label: 'Channel Bottom Button',
      value: appState.channelBottomButton,
      items: const {0: 'Hidden', 1: 'Mute/Unmute', 2: 'Discuss (fallback)'},
      onChanged: (v) => appState.setChannelBottomButton(v),
    );
    b.addSettingToggle(
      label: 'Quick Admin Shortcuts',
      subtitle: 'Enable quick admin action shortcuts',
      value: appState.quickAdminShortcuts,
      onChanged: (v) => appState.setQuickAdminShortcuts(v),
    );
    b.addSettingToggle(
      label: 'Message Shot',
      subtitle: 'Share styled message screenshots',
      value: appState.showMessageShot,
      onChanged: (v) => appState.setShowMessageShot(v),
    );
    b.addSkip();
    b.addDividerText(
        'Generate and share styled screenshots of messages.');
    b.addSkip();

    b.addSectionDivider();

    // Messages / Marks (§54.11) — matches AyuGram BuildMarks()
    b.addSubsectionTitle('Messages');
    b.addWidget(_MessagePreviewStandalone(
      bubbleRadius: appState.bubbleRadius,
      showTail: !appState.removeTail,
      simpleQuotesAndReplies: appState.simpleQuotesAndReplies,
      semiTransparentDeleted: appState.semiTransparentDeleted,
      replaceMarksWithIcons: appState.replaceMarksWithIcons,
      deletedMark: appState.deletedMark,
      editedMark: appState.editedMark,
      hideFastShare: appState.hideFastShare,
      isDark: isDark,
    ));
    b.addSettingToggle(
      label: 'Replace marks with icons',
      value: appState.replaceMarksWithIcons,
      onChanged: (v) => appState.setReplaceMarksWithIcons(v),
    );
    if (!appState.replaceMarksWithIcons) {
      b.addWidget(_EditMarkButton(
        label: 'Deleted mark text',
        currentValue: appState.deletedMark,
        defaultValue: '\u{1F9F9}',
        onSaved: (v) => appState.setDeletedMark(v),
        isDark: isDark,
      ));
      b.addWidget(_EditMarkButton(
        label: 'Edited mark text',
        currentValue: appState.editedMark,
        defaultValue: 'edited',
        onSaved: (v) => appState.setEditedMark(v),
        isDark: isDark,
      ));
    }
    b.addSettingToggle(
      label: 'Remove message tail',
      subtitle: 'Clean rounded rectangles without tail accent',
      value: appState.removeTail,
      onChanged: (v) => appState.setRemoveTail(v),
    );
    b.addSettingToggle(
      label: 'Hide side "Share" button',
      subtitle: 'Hide the circular forward button on messages',
      value: appState.hideFastShare,
      onChanged: (v) => appState.setHideFastShare(v),
    );
    b.addSettingToggle(
      label: 'Simple quotes and replies',
      subtitle: 'Uniform reply bar style without colorful accents',
      value: appState.simpleQuotesAndReplies,
      onChanged: (v) => appState.setSimpleQuotesAndReplies(v),
    );
    b.addSettingToggle(
      label: 'Semi-transparent deleted messages',
      value: appState.semiTransparentDeleted,
      onChanged: (v) => appState.setSemiTransparentDeleted(v),
      showBetaBadge: true,
    );

    b.addSectionDivider();

    // Bubble radius & wide multiplier — matches AyuGram BuildWideMessagesMultiplier()
    // Order: messageBubbleRadius first, then wideMultiplier
    b.addWidget(_BubbleRadiusSlider(
      value: appState.bubbleRadius,
      onChanged: (v) => appState.setBubbleRadius(v),
      isDark: isDark,
    ));

    b.addSectionDivider();

    b.addWidget(_WideMultiplierSlider(
      value: appState.wideMultiplier,
      onChanged: (v) => appState.setWideMultiplier(v),
      isDark: isDark,
    ));

    b.addSectionDivider();

    // Context Menu Elements (§54.7)
    b.addSubsectionTitle('Context Menu Elements');
    for (final item in _contextMenuItems(appState)) {
      b.addChooseButton(
        label: item.label,
        value: item.value,
        items: const {0: 'Hidden', 1: 'Shown', 2: 'Extended Menu'},
        onChanged: item.onChanged,
      );
    }
    b.addSkip();
    b.addDividerText(
      'Extended menu items will be displayed if you hold CTRL or SHIFT '
      'while right-clicking on the message.',
    );
    b.addSkip();

    b.addSectionDivider();

    // Message Field Elements (§54.9)
    b.addSubsectionTitle('Message Field Elements');
    b.addSettingToggle(
      label: 'Attach',
      subtitle: 'Show paperclip button in compose area',
      value: appState.showAttachButton,
      onChanged: (v) => appState.setShowAttachButton(v),
    );
    b.addSettingToggle(
      label: 'Commands',
      subtitle: 'Show bot commands (/) button',
      value: appState.showCommandsButton,
      onChanged: (v) => appState.setShowCommandsButton(v),
    );
    b.addSettingToggle(
      label: 'TTL',
      subtitle: 'Show auto-delete timer button',
      value: appState.showAutoDeleteButton,
      onChanged: (v) => appState.setShowAutoDeleteButton(v),
    );
    b.addSettingToggle(
      label: 'Emoji',
      subtitle: 'Show emoji button in compose area',
      value: appState.showEmojiButton,
      onChanged: (v) => appState.setShowEmojiButton(v),
    );
    b.addSettingToggle(
      label: 'Voice',
      subtitle: 'Show microphone/voice button',
      value: appState.showMicrophoneButton,
      onChanged: (v) => appState.setShowMicrophoneButton(v),
    );
    b.addSettingToggle(
      label: 'Gift',
      subtitle: 'Show gift button in DMs',
      value: appState.showGiftButton,
      onChanged: (v) => appState.setShowGiftButton(v),
    );
    b.addSettingToggle(
      label: 'AI Editor',
      subtitle: 'Show AI editor button in compose area',
      value: appState.showAiEditorButton,
      onChanged: (v) => appState.setShowAiEditorButton(v),
    );

    b.addSectionDivider();

    // Message Field Popups (§54.9)
    b.addSubsectionTitle('Message Field Popups');
    b.addSettingToggle(
      label: 'Attach popup',
      subtitle: 'Show file/poll picker when pressing attach',
      value: appState.showAttachPopup,
      onChanged: (v) => appState.setShowAttachPopup(v),
    );
    b.addSettingToggle(
      label: 'Emoji popup',
      subtitle: 'Show emoji/sticker panel when pressing emoji',
      value: appState.showEmojiPopup,
      onChanged: (v) => appState.setShowEmojiPopup(v),
    );

    b.addSkip(24);

    return ayuSettingsScaffold(
      context: context,
      title: 'Chats',
      children: b.build(),
    );
  }

  List<_ContextMenuItem> _contextMenuItems(AppState s) => [
        _ContextMenuItem('Reactions Panel', s.showReactionsPanelInContextMenu,
            (v) => s.setShowReactionsPanelInContextMenu(v)),
        _ContextMenuItem('Views Panel', s.showViewsPanelInContextMenu,
            (v) => s.setShowViewsPanelInContextMenu(v)),
        _ContextMenuItem('Hide Message', s.showHideMessageInContextMenu,
            (v) => s.setShowHideMessageInContextMenu(v)),
        _ContextMenuItem('User Messages', s.showUserMessagesInContextMenu,
            (v) => s.setShowUserMessagesInContextMenu(v)),
        _ContextMenuItem('Message Details', s.showMessageDetailsInContextMenu,
            (v) => s.setShowMessageDetailsInContextMenu(v)),
        _ContextMenuItem('Repeat Message', s.showRepeatMessageInContextMenu,
            (v) => s.setShowRepeatMessageInContextMenu(v)),
        if (s.filtersEnabled)
          _ContextMenuItem('Add Filter', s.showAddFilterInContextMenu,
              (v) => s.setShowAddFilterInContextMenu(v)),
      ];
}

class _ContextMenuItem {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  _ContextMenuItem(this.label, this.value, this.onChanged);
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
    _localValue = widget.value.clamp(1.0, 4.0);
    _committedValue = _localValue;
  }

  @override
  void didUpdateWidget(_WideMultiplierSlider old) {
    super.didUpdateWidget(old);
    if ((old.value - widget.value).abs() > 0.001) {
      _localValue = widget.value.clamp(1.0, 4.0);
      _committedValue = _localValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = context.palette.windowBgActive;
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
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: context.palette.windowBgActive)),
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
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 7.5),
            ),
            child: Slider(
              value: _localValue,
              min: 1.0,
              max: 4.0,
              divisions: 60,
              onChanged: (v) => setState(() => _localValue = v),
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
                  onCancel: () =>
                      setState(() => _localValue = _committedValue),
                );
              },
            ),
          ),
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Text(
              'Change message width for better display on wide monitors.',
              style: TextStyle(fontSize: 13, color: subtitleColor),
            ),
          ),
          const SizedBox(height: 7),
        ],
      ),
    );
  }
}

class _BubbleRadiusSlider extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final bool isDark;

  const _BubbleRadiusSlider({
    required this.value,
    required this.onChanged,
    required this.isDark,
  });

  @override
  State<_BubbleRadiusSlider> createState() => _BubbleRadiusSliderState();
}

class _BubbleRadiusSliderState extends State<_BubbleRadiusSlider> {
  late int _localValue;
  late int _committedValue;

  @override
  void initState() {
    super.initState();
    _localValue = widget.value;
    _committedValue = widget.value;
  }

  @override
  void didUpdateWidget(_BubbleRadiusSlider old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _localValue = widget.value;
      _committedValue = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = context.palette.windowBgActive;
    final textColor = widget.isDark ? Colors.white : Colors.black87;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Message Bubble Radius',
                    style: TextStyle(fontSize: 14, color: textColor)),
              ),
              Text('$_localValue',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: accentColor)),
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
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 7.5),
            ),
            child: Slider(
              value: _localValue.toDouble(),
              min: 0,
              max: 16,
              divisions: 16,
              onChanged: (v) {
                final newVal = v.round();
                setState(() => _localValue = newVal);
                widget.onChanged(newVal);
              },
              onChangeEnd: (v) {
                final newVal = v.round();
                if (newVal == _committedValue) {
                  return;
                }
                _committedValue = newVal;
                showConfirmBox(
                  context,
                  title: 'Restart Required',
                  text: 'Some settings will be applied after restarting.',
                  confirmText: 'OK',
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EditMarkButton extends StatelessWidget {
  final String label;
  final String currentValue;
  final String defaultValue;
  final ValueChanged<String> onSaved;
  final bool isDark;

  const _EditMarkButton({
    required this.label,
    required this.currentValue,
    required this.defaultValue,
    required this.onSaved,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final valueColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    final displayValue = currentValue.isEmpty ? defaultValue : currentValue;

    return InkWell(
      onTap: () => _showEditMarkBox(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 14, color: textColor)),
            ),
            Text(displayValue,
                style: TextStyle(fontSize: 14, color: valueColor)),
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
    showTelegramBox(
      context: context,
      builder: (ctx) => _EditMarkBoxContent(
        title: label,
        currentValue: currentValue,
        defaultValue: defaultValue,
        onSaved: onSaved,
      ),
    );
  }
}

class _EditMarkBoxContent extends StatefulWidget {
  final String title;
  final String currentValue;
  final String defaultValue;
  final ValueChanged<String> onSaved;

  const _EditMarkBoxContent({
    required this.title,
    required this.currentValue,
    required this.defaultValue,
    required this.onSaved,
  });

  @override
  State<_EditMarkBoxContent> createState() => _EditMarkBoxContentState();
}

class _EditMarkBoxContentState extends State<_EditMarkBoxContent> {
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

  void _save() {
    widget.onSaved(_controller.text);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return TelegramBox(
      title: widget.title,
      onConfirm: _save,
      content: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: TextField(
          controller: _controller,
          autofocus: true,
          style: TextStyle(fontSize: 14, color: p.boxTextFg),
          decoration: InputDecoration(
            hintText: widget.title,
            hintStyle: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: p.boxTextFg.withValues(alpha: 0.4)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: p.windowBgActive),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: p.windowBgActive, width: 2),
            ),
          ),
        ),
      ),
      buttons: [
        TelegramBoxButton(
          text: 'Reset',
          isLeft: true,
          onPressed: () {
            _controller.text = widget.defaultValue;
          },
        ),
        TelegramBoxButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        TelegramBoxButton(
          text: 'Save',
          onPressed: _save,
        ),
      ],
    );
  }
}

class _MessagePreviewStandalone extends StatelessWidget {
  final int bubbleRadius;
  final bool showTail;
  final bool simpleQuotesAndReplies;
  final bool semiTransparentDeleted;
  final bool replaceMarksWithIcons;
  final String deletedMark;
  final String editedMark;
  final bool hideFastShare;
  final bool isDark;

  const _MessagePreviewStandalone({
    required this.bubbleRadius,
    required this.showTail,
    required this.simpleQuotesAndReplies,
    required this.semiTransparentDeleted,
    required this.replaceMarksWithIcons,
    required this.deletedMark,
    required this.editedMark,
    required this.hideFastShare,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final appState = context.read<AppState>();
    final userName = appState.activeAccount?.displayName ?? 'You';
    final radiusLarge = bubbleRadius.toDouble();
    final radiusSmall = showTail
        ? (radiusLarge * 6 / 16).clamp(0.0, 6.0)
        : radiusLarge;
    final nameColor = simpleQuotesAndReplies
        ? p.windowBgActive
        : p.historyPeer4NameFg;
    final quoteBarColor = simpleQuotesAndReplies
        ? p.windowBgActive
        : p.msgOutReplyBarColor;
    final deletedOpacity = semiTransparentDeleted ? 0.7 : 1.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF0E1621)
                : const Color(0xFFF0F0F0),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 240),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: p.msgInBg,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(radiusLarge),
                      topRight: Radius.circular(radiusLarge),
                      bottomLeft: Radius.circular(radiusSmall),
                      bottomRight: Radius.circular(radiusLarge),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: p.msgInShadow,
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(userName,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: nameColor)),
                      const SizedBox(height: 2),
                      Text('Hey, check this out!',
                          style: TextStyle(
                              fontSize: 13, color: p.historyTextInFg)),
                      const SizedBox(height: 2),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text('12:00',
                            style: TextStyle(
                                fontSize: 11, color: p.msgInDateFg)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Opacity(
                  opacity: deletedOpacity,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 260),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 6),
                          decoration: BoxDecoration(
                            color: p.msgOutBg,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(radiusLarge),
                              topRight: Radius.circular(radiusLarge),
                              bottomLeft: Radius.circular(radiusLarge),
                              bottomRight: Radius.circular(radiusSmall),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: p.msgOutShadow,
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.only(
                                    left: 8, top: 3, bottom: 3, right: 6),
                                decoration: BoxDecoration(
                                  border: Border(
                                    left: BorderSide(
                                        width: 2, color: quoteBarColor),
                                  ),
                                  color: simpleQuotesAndReplies
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
                                    Text(userName,
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: nameColor)),
                                    Text('Hey, check this out!',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: p.historyTextOutFg
                                                .withValues(alpha: 0.7))),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                  'Sure, looks great to me!',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: p.historyTextOutFg)),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  const Spacer(),
                                  ..._buildMarks(p.msgOutDateFg),
                                  Text('12:01',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: p.msgOutDateFg)),
                                  const SizedBox(width: 3),
                                  Icon(Icons.done_all,
                                      size: 14, color: p.msgOutDateFg),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!hideFastShare) ...[
                        const SizedBox(width: 4),
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: p.msgServiceBg,
                          ),
                          child: Icon(Icons.shortcut,
                              size: 16, color: p.msgServiceFg),
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

  List<Widget> _buildMarks(Color metaColor) {
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
          child: Text(deletedMark,
              style: TextStyle(fontSize: 11, color: metaColor)),
        ));
      }
      if (editedMark.isNotEmpty) {
        marks.add(Padding(
          padding: const EdgeInsets.only(right: 3),
          child: Text(editedMark,
              style: TextStyle(fontSize: 11, color: metaColor)),
        ));
      } else {
        marks.add(Padding(
          padding: const EdgeInsets.only(right: 3),
          child: Text('edited',
              style: TextStyle(fontSize: 11, color: metaColor)),
        ));
      }
    }
    return marks;
  }
}
