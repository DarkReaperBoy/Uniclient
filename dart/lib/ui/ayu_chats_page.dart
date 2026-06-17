
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../theme/telegram_palette.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/app_state.dart';
import 'ayu_section_builder.dart';
import 'ayu_toggle.dart';
import 'confirm_box.dart';

class AyuChatsPage extends StatefulWidget {
  const AyuChatsPage({super.key});

  @override
  State<AyuChatsPage> createState() => _AyuChatsPageState();
}

class _AyuChatsPageState extends State<AyuChatsPage> {
  // Live bubble-radius preview channel — the Dart analogue of AyuGram's shared
  // `previewState->widget`. The bubble-radius slider pokes this ValueNotifier on
  // every drag frame so ONLY the message preview (a ValueListenableBuilder)
  // re-renders live; the value is persisted to AppState — and the whole watched
  // page rebuilt — exactly once, on release. This delivers the live feedback the
  // preview-next-to-slider exists for WITHOUT the per-frame full-page rebuild a
  // notifyListeners()-on-drag would cause (settings_chats.cpp:255-259).
  final ValueNotifier<int> _previewBubbleRadius = ValueNotifier<int>(0);
  bool _previewBubbleRadiusSeeded = false;

  @override
  void dispose() {
    _previewBubbleRadius.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Seed the live preview from the persisted radius on first build (mirrors
    // AyuGram seeding the preview from messageBubbleRadius() at construction).
    // Safe to assign during this first build: the preview's ValueListenableBuilder
    // is not mounted yet, so there is no listener to notify. Afterwards the value
    // changes only via the slider (live during drag, persisted on release), so we
    // never mutate it during a later build.
    if (!_previewBubbleRadiusSeeded) {
      _previewBubbleRadius.value = appState.bubbleRadius;
      _previewBubbleRadiusSeeded = true;
    }

    final b = AyuSectionBuilder(
        isDark: isDark, useMaterial: appState.materialSwitches);

    b.addSkip();

    // Stickers & Emoji (§54.11)
    b.addSubsectionTitle('Stickers & Emoji');
    b.addSettingToggle(
      label: 'Show only added emojis/stickers',
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
      // ANY-semantics: the master shows ON when ANY child is checked (any
      // reaction type hidden) and clicking it un-hides all — matching AyuGram's
      // `.toggledWhenAll = false` (settings_chats.cpp:67, count != 0 in
      // settings_ayu_utils.cpp:216-222). Omitting this defaults to ALL-semantics:
      // the master would read OFF unless every type is hidden, and clicking it
      // would *hide all* — wrong displayed state plus an inverted click result.
      toggledWhenAll: false,
    );
    b.addSectionDivider();
    b.addSlider(
      label: 'Recent Stickers Count',
      steps: 201,
      current: appState.recentStickersCount,
      indexToValue: (i) => i,
      formatLabel: (v) => '$v',
      // Label-only live update during drag; persist once on release. Matches
      // AyuGram's `.onChanged = nullptr` + persist-in-`.onFinalChanged`
      // (settings_chats.cpp:82-87). Persisting per drag frame here would call
      // setRecentStickersCount → notifyListeners → rebuild this whole watched
      // page every frame — the exact anti-pattern the bubble/wide sliders avoid.
      onChanged: null,
      onFinalChanged: (v) => appState.setRecentStickersCount(v),
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
      value: appState.quickAdminShortcuts,
      onChanged: (v) => appState.setQuickAdminShortcuts(v),
    );
    b.addSettingToggle(
      label: 'Message Shot',
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
    b.addWidget(Builder(builder: (ctx) {
      final subtextColor = isDark
          ? const Color(0xFF6D7F8F)
          : const Color(0xFF999999);
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
        child: Text(
          'Visual approximation only — actual rendering may differ',
          style: TextStyle(fontSize: 11, color: subtextColor, fontStyle: FontStyle.italic),
        ),
      );
    }));
    b.addWidget(const SizedBox(height: 4));
    b.addWidget(_MessagePreviewStandalone(
      bubbleRadiusListenable: _previewBubbleRadius,
      showTail: !appState.removeTail,
      simpleQuotesAndReplies: appState.simpleQuotesAndReplies,
      semiTransparentDeleted: appState.semiTransparentDeleted,
      replaceMarksWithIcons: appState.replaceMarksWithIcons,
      deletedMark: appState.deletedMark,
      editedMark: appState.editedMark,
      hideFastShare: appState.hideFastShare,
      userName: appState.activeAccount?.displayName ?? 'You',
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
        defaultValue: TrStrings.lngEdited(),
        onSaved: (v) => appState.setEditedMark(v),
        isDark: isDark,
      ));
    }
    b.addSettingToggle(
      label: 'Remove message tail',
      value: appState.removeTail,
      onChanged: (v) => appState.setRemoveTail(v),
    );
    b.addSettingToggle(
      label: 'Hide side "Share" button',
      value: appState.hideFastShare,
      onChanged: (v) => appState.setHideFastShare(v),
    );
    b.addSettingToggle(
      label: 'Simple quotes and replies',
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
      // Live preview: pokes the shared notifier every drag frame so only the
      // message preview re-renders (AyuGram: previewState->widget->setBubbleRadius
      // each frame, settings_chats.cpp:255-259). Persist stays in onChangeEnd.
      onLivePreview: (v) => _previewBubbleRadius.value = v,
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
        // Every context-menu choose button shares ONE generic box title
        // (ayu_SettingsContextMenuTitle = "Choose when to show the item") while
        // each row label differs ("Reactions Panel", "Views Panel", …) —
        // settings_chats.cpp:309-310. Without this the box would reuse the row
        // label (e.g. a box titled "Reactions Panel" instead of the generic one).
        boxTitle: 'Choose when to show the item',
        value: item.value,
        items: const {0: 'Hidden', 1: 'Shown', 2: 'Extended Menu'},
        onChanged: item.onChanged,
        icon: item.icon,
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
    // Every row carries the leading icon of the compose-bar button it controls,
    // matching AyuGram (.icon = messageFieldAttach/Commands/TTL/Emoji/Voice,
    // settingsButtonIconGift, messageFieldCocoonAi — settings_chats.cpp:386-428).
    // An icon also switches the row to the wider icon layout (ayu_builder.cpp:75),
    // which _AyuSettingToggle applies automatically when `icon` is non-null.
    b.addSubsectionTitle('Message Field Elements');
    b.addSettingToggle(
      label: 'Attach',
      value: appState.showAttachButton,
      onChanged: (v) => appState.setShowAttachButton(v),
      icon: Icons.attach_file,
    );
    b.addSettingToggle(
      label: 'Commands',
      value: appState.showCommandsButton,
      onChanged: (v) => appState.setShowCommandsButton(v),
      icon: Icons.code,
    );
    b.addSettingToggle(
      label: 'TTL',
      value: appState.showAutoDeleteButton,
      onChanged: (v) => appState.setShowAutoDeleteButton(v),
      icon: Icons.timer_outlined,
    );
    b.addSettingToggle(
      label: 'Emoji',
      value: appState.showEmojiButton,
      onChanged: (v) => appState.setShowEmojiButton(v),
      icon: Icons.emoji_emotions_outlined,
    );
    b.addSettingToggle(
      label: 'Voice',
      value: appState.showMicrophoneButton,
      onChanged: (v) => appState.setShowMicrophoneButton(v),
      icon: Icons.mic_none,
    );
    b.addSettingToggle(
      label: 'Gift',
      value: appState.showGiftButton,
      onChanged: (v) => appState.setShowGiftButton(v),
      icon: Icons.card_giftcard,
    );
    b.addSettingToggle(
      label: 'AI Editor',
      value: appState.showAiEditorButton,
      onChanged: (v) => appState.setShowAiEditorButton(v),
      icon: Icons.auto_awesome,
    );

    b.addSectionDivider();

    // Message Field Popups (§54.9) — AyuGram reuses the attach/emoji field icons
    // here (.icon = messageFieldAttachIcon / messageFieldEmojiIcon,
    // settings_chats.cpp:437-450).
    b.addSubsectionTitle('Message Field Popups');
    b.addSettingToggle(
      label: 'Attach popup',
      value: appState.showAttachPopup,
      onChanged: (v) => appState.setShowAttachPopup(v),
      icon: Icons.attach_file,
    );
    b.addSettingToggle(
      label: 'Emoji popup',
      value: appState.showEmojiPopup,
      onChanged: (v) => appState.setShowEmojiPopup(v),
      icon: Icons.emoji_emotions_outlined,
    );

    b.addSkip(24);

    return ayuSettingsScaffold(
      context: context,
      title: 'Chats',
      children: b.build(),
    );
  }

  List<_ContextMenuItem> _contextMenuItems(AppState s) => [
        _ContextMenuItem('Reactions Panel', Icons.emoji_emotions_outlined,
            s.showReactionsPanelInContextMenu,
            (v) => s.setShowReactionsPanelInContextMenu(v)),
        _ContextMenuItem('Views Panel', Icons.visibility_outlined,
            s.showViewsPanelInContextMenu,
            (v) => s.setShowViewsPanelInContextMenu(v)),
        _ContextMenuItem('Hide Message', Icons.clear_all,
            s.showHideMessageInContextMenu,
            (v) => s.setShowHideMessageInContextMenu(v)),
        _ContextMenuItem('User Messages', Icons.timer_outlined,
            s.showUserMessagesInContextMenu,
            (v) => s.setShowUserMessagesInContextMenu(v)),
        _ContextMenuItem('Message Details', Icons.info_outline,
            s.showMessageDetailsInContextMenu,
            (v) => s.setShowMessageDetailsInContextMenu(v)),
        _ContextMenuItem('Repeat Message', Icons.repeat,
            s.showRepeatMessageInContextMenu,
            (v) => s.setShowRepeatMessageInContextMenu(v)),
        if (s.filtersEnabled)
          _ContextMenuItem('Add Filter', Icons.create_new_folder_outlined,
              s.showAddFilterInContextMenu,
              (v) => s.setShowAddFilterInContextMenu(v)),
      ];
}

class _ContextMenuItem {
  final String label;
  final IconData icon;
  final int value;
  final ValueChanged<int> onChanged;
  _ContextMenuItem(this.label, this.icon, this.value, this.onChanged);
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
                _committedValue = snapped;
                widget.onChanged(snapped);
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
  // Live preview callback fired on every drag frame (AyuGram slider .onChanged).
  // Persist (this.onChanged) still fires only on release, in onChangeEnd.
  final ValueChanged<int>? onLivePreview;
  final bool isDark;

  const _BubbleRadiusSlider({
    required this.value,
    required this.onChanged,
    this.onLivePreview,
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
              // Drag never persists per-frame (that would fire setBubbleRadius →
              // notifyListeners → full page rebuild every frame). Instead it pokes
              // the preview-only live channel so just the message preview updates
              // (AyuGram previewState->widget->setBubbleRadius every frame). The
              // actual setting persists solely in onChangeEnd.
              onChanged: (v) {
                final idx = v.round();
                setState(() => _localValue = idx);
                widget.onLivePreview?.call(idx);
              },
              onChangeEnd: (v) {
                final newVal = v.round();
                // Keep the preview exactly at the released value (covers a
                // track-tap that produced no intermediate onChanged frame).
                widget.onLivePreview?.call(newVal);
                if (newVal == _committedValue) return;
                _committedValue = newVal;
                widget.onChanged(newVal);
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
  final _focusNode = FocusNode();
  bool _showError = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentValue);
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (_showError && _controller.text.trim().isNotEmpty) {
      setState(() => _showError = false);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim().isEmpty) {
      _focusNode.requestFocus();
      setState(() => _showError = true);
    } else {
      _save();
    }
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
      onConfirm: _submit,
      content: Padding(
        padding: const EdgeInsets.fromLTRB(24, 2, 24, 14),
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          onSubmitted: (_) => _submit(),
          style: TextStyle(fontSize: 14, color: p.boxTextFg),
          decoration: InputDecoration(
            hintText: widget.title,
            hintStyle: TextStyle(fontSize: 14, color: p.placeholderFg),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: _showError ? p.activeLineFgError : p.inputBorderFg,
              ),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: _showError ? p.activeLineFgError : p.activeLineFg,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ),
      buttons: [
        TelegramBoxButton(
          text: TrStrings.lngAyuBoxActionReset(),
          isLeft: true,
          onPressed: () {
            _controller.text = widget.defaultValue;
          },
        ),
        TelegramBoxButton(
          // AyuGram's Save button calls save() directly — no validation — so the
          // user can clear a mark (edit_mark_box.cpp:50-54). Only the Enter key
          // runs submit()/validates (edit_mark_box.cpp:61-67,73-80), wired via the
          // box's onConfirm and the field's onSubmitted above.
          text: TrStrings.lngSettingsSave(),
          onPressed: _save,
        ),
        TelegramBoxButton(
          text: TrStrings.lngCancel(),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _MessagePreviewStandalone extends StatelessWidget {
  // Live preview radius (see _AyuChatsPageState._previewBubbleRadius). Listened
  // to so a bubble-radius drag re-renders only this widget, not the whole page.
  final ValueListenable<int> bubbleRadiusListenable;
  final bool showTail;
  final bool simpleQuotesAndReplies;
  final bool semiTransparentDeleted;
  final bool replaceMarksWithIcons;
  final String deletedMark;
  final String editedMark;
  final bool hideFastShare;
  final String userName;
  final bool isDark;

  const _MessagePreviewStandalone({
    required this.bubbleRadiusListenable,
    required this.showTail,
    required this.simpleQuotesAndReplies,
    required this.semiTransparentDeleted,
    required this.replaceMarksWithIcons,
    required this.deletedMark,
    required this.editedMark,
    required this.hideFastShare,
    required this.userName,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    // Listen to the live preview radius so dragging the bubble-radius slider
    // re-renders ONLY this preview, not the whole watched settings page. Mirrors
    // AyuGram MessagePreview::setBubbleRadius → refresh() (message_preview.cpp:194-200).
    return ValueListenableBuilder<int>(
      valueListenable: bubbleRadiusListenable,
      builder: (context, bubbleRadius, _) => _buildBubble(context, bubbleRadius),
    );
  }

  // Telegram's corner-radius mapping (ui/chat/chat_style_radius.cpp:39-48):
  // scales a target corner radius `maximum` by the slider value across its 0..16
  // range with round-half-up integer division, clamped to [0, maximum]. AyuGram
  // feeds the live preview the raw slider value via SetBubbleRadiusOverride
  // (message_preview.cpp:169), which drives both BubbleRadiusLarge/Small().
  double _mapBubbleRadius(int sliderValue, int maximum) {
    const int sliderMax = 16;
    if (sliderValue <= 0 || maximum <= 0) {
      return 0;
    } else if (sliderValue >= sliderMax) {
      return maximum.toDouble();
    }
    final result = (sliderValue * maximum + (sliderMax ~/ 2)) ~/ sliderMax;
    return (result < 0 ? 0 : (result > maximum ? maximum : result)).toDouble();
  }

  Widget _buildBubble(BuildContext context, int bubbleRadius) {
    final p = context.palette;
    final radiusLarge = bubbleRadius.toDouble();
    // Tail-side (bottom-left) corner. AyuGram derives it as
    // MapBubbleRadius(sliderValue, st::bubbleRadiusSmall), where bubbleRadiusSmall =
    // roundRadiusLarge = 6px (chat.style:434, basic.style:103) — so the tail corner
    // is 6px at the default radius (16) and shrinks with the slider (≈3px @8,
    // ≈2px @4), never pinned at a constant. With the tail hidden every corner is large.
    const int bubbleRadiusSmall = 6;
    final radiusSmall = showTail
        ? _mapBubbleRadius(bubbleRadius, bubbleRadiusSmall)
        : radiusLarge;
    final senderColor = simpleQuotesAndReplies
        ? p.windowBgActive
        : p.historyPeer4NameFg;
    final replyAuthorColor = simpleQuotesAndReplies
        ? p.windowBgActive
        : p.historyPeer1NameFg;
    final quoteBarColor = simpleQuotesAndReplies
        ? p.windowBgActive
        : p.msgInReplyBarColor;
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
          child: Align(
            alignment: Alignment.centerLeft,
            child: Opacity(
              opacity: deletedOpacity,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 280),
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
                          Text('AyuGram Releases',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: senderColor)),
                          const SizedBox(height: 2),
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
                                        color: replyAuthorColor)),
                                Text('Update wehn?',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: p.historyTextInFg
                                            .withValues(alpha: 0.7))),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                              'You need to go outside and touch some grass...',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: p.historyTextInFg)),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              const Spacer(),
                              ..._buildMarks(p.msgInDateFg),
                              Text('12:00',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: p.msgInDateFg)),
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
                      // Fast-share/forward swoosh (st::historyFastShareIcon) —
                      // a right-pointing curved arrow, i.e. a horizontally
                      // mirrored reply arrow. Icons.shortcut is an angular
                      // redirect glyph, not Telegram's curved forward arrow.
                      child: Transform.flip(
                        flipX: true,
                        child: Icon(Icons.reply,
                            size: 16, color: p.msgServiceFg),
                      ),
                    ),
                  ],
                ],
              ),
            ),
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
          child: Text(TrStrings.lngEdited(),
              style: TextStyle(fontSize: 11, color: metaColor)),
        ));
      }
    }
    return marks;
  }
}
