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
    b.addSectionTitle('Stickers & Emoji');
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
    b.addSlider(
      label: 'Recent Stickers Count',
      value: appState.recentStickersCount.toDouble(),
      min: 0,
      max: 200,
      divisions: 200,
      valueLabel: '${appState.recentStickersCount}',
      onChanged: (v) => appState.setRecentStickersCount(v.round()),
    );

    b.addSectionDivider();

    // Channels (§54.11)
    b.addSectionTitle('Channels');
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
    b.addSettingToggle(
      label: 'Hide side "Share" button',
      subtitle: 'Hide the circular forward button on messages',
      value: appState.hideFastShare,
      onChanged: (v) => appState.setHideFastShare(v),
    );

    b.addSectionDivider();

    // Messages (§54.11)
    b.addSectionTitle('Messages');
    b.addWidget(_WideMultiplierSlider(
      value: appState.wideMultiplier,
      onChanged: (v) => appState.setWideMultiplier(v),
      isDark: isDark,
    ));
    b.addWidget(_BubbleRadiusSection(
      value: appState.bubbleRadius,
      showTail: !appState.removeTail,
      simpleQuotes: appState.simpleQuotes,
      semiTransparentDeleted: appState.semiTransparentDeleted,
      replaceMarksWithIcons: appState.replaceMarksWithIcons,
      deletedMark: appState.deletedMark,
      editedMark: appState.editedMark,
      onChanged: (v) => appState.setBubbleRadius(v),
      isDark: isDark,
    ));
    b.addSettingToggle(
      label: 'Remove message tail',
      subtitle: 'Clean rounded rectangles without tail accent',
      value: appState.removeTail,
      onChanged: (v) => appState.setRemoveTail(v),
    );
    b.addSettingToggle(
      label: 'Simple quotes and replies',
      subtitle: 'Uniform reply bar style without colorful accents',
      value: appState.simpleQuotes,
      onChanged: (v) => appState.setSimpleQuotes(v),
    );

    b.addSectionDivider();

    // Context Menu Elements (§54.7)
    b.addSectionTitle('Context Menu Elements');
    b.addDescription(
      'Extended menu items will be displayed if you hold CTRL or SHIFT '
      'while right-clicking on the message.',
    );
    for (final item in _contextMenuItems(appState)) {
      b.addChooseButton(
        label: item.label,
        value: item.value,
        items: const {0: 'Shown', 1: 'Hidden', 2: 'Extended Menu'},
        onChanged: item.onChanged,
      );
    }

    b.addSectionDivider();

    // Message Field Elements (§54.9)
    b.addSectionTitle('Message Field Elements');
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
    b.addSectionTitle('Message Field Popups');
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                            color: widget.isDark
                                ? Colors.white
                                : Colors.black87)),
                  ),
                  Text('$_localValue',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: context.palette.windowBgActive)),
                ],
              ),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: context.palette.windowBgActive,
                  inactiveTrackColor: widget.isDark
                      ? const Color(0xFF2B3C4C)
                      : const Color(0xFFD5D5D5),
                  thumbColor: context.palette.windowBgActive,
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
                  onChanged: (v) =>
                      setState(() => _localValue = v.round()),
                  onChangeEnd: (v) {
                    final newVal = v.round();
                    if (newVal == _committedValue) return;
                    showConfirmBox(
                      context,
                      title: 'Restart Required',
                      text:
                          'Bubble radius will be applied after restarting.',
                      confirmText: 'Apply',
                      cancelText: 'Cancel',
                      onConfirm: () {
                        _committedValue = newVal;
                        widget.onChanged(newVal);
                      },
                      onCancel: () =>
                          setState(() => _localValue = _committedValue),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
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
    final textColor =
        isDark ? Colors.white.withValues(alpha: 0.87) : Colors.black87;
    final metaColor =
        isDark ? const Color(0xFF6D8DA0) : const Color(0xFF5E9E5E);
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
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 240),
                padding: const EdgeInsets.symmetric(
                    horizontal: 11, vertical: 6),
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
                          style:
                              TextStyle(fontSize: 11, color: metaColor)),
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
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 260),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 11, vertical: 6),
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
                      Container(
                        padding: const EdgeInsets.only(
                            left: 8, top: 3, bottom: 3, right: 6),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                                width: 2, color: quoteBarColor),
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
                                    color: textColor.withValues(
                                        alpha: 0.7))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('You need to touch some grass.',
                          style:
                              TextStyle(fontSize: 13, color: textColor)),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Spacer(),
                          ..._buildMarks(textColor, metaColor),
                          Text('12:01',
                              style: TextStyle(
                                  fontSize: 11, color: metaColor)),
                          const SizedBox(width: 3),
                          Icon(Icons.done_all,
                              size: 14, color: metaColor),
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
