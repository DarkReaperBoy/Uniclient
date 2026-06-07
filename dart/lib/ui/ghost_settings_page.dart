import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import 'ayu_section_builder.dart' show ExpandArrowPainter;
import 'ayu_toggle.dart';
import 'confirm_box.dart';
import 'telegram_toast.dart';

class GhostSettingsPage extends StatefulWidget {
  const GhostSettingsPage({super.key});

  @override
  State<GhostSettingsPage> createState() => _GhostSettingsPageState();
}

class _GhostSettingsPageState extends State<GhostSettingsPage> {
  String? _selectedUserId;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    final activeCount = appState.accounts.length;
    if (activeCount <= 1 && !appState.useGlobalGhostMode) {
      final userId = appState.activeAccount?.selfUserId ?? '';
      if (userId.isNotEmpty) {
        appState.copyGhostToGlobal(userId);
      }
      appState.setUseGlobalGhostMode(true);
    }
  }

  String _resolveKey(AppState appState) {
    return appState.resolveGhostKey(_selectedUserId);
  }

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

    final key = _resolveKey(appState);
    final gs = appState.ensureGhostForKey(key);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF17212B) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        title: Text('AyuGram',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Builder(builder: (_) {
        final _lvKids = <Widget>[
          const SizedBox(height: 7),
          // ── Ghost essentials (§51.2.1) ──
          _GhostEssentialsHeader(
            sectionLabelColor: sectionLabelColor,
            accounts: appState.accounts,
            useGlobal: appState.useGlobalGhostMode,
            activeAccount: _selectedUserId == null
                ? appState.activeAccount
                : appState.accounts.cast<AccountInfo?>().firstWhere(
                    (a) => a?.selfUserId == _selectedUserId,
                    orElse: () => appState.activeAccount,
                  ),
            onScopeChanged: (bool global, String? userId) {
              if (global) {
                appState.setUseGlobalGhostMode(true);
                setState(() => _selectedUserId = null);
                showTelegramToast(context,
                    'Switched to same settings for all accounts.');
              } else {
                appState.setUseGlobalGhostMode(false);
                setState(() => _selectedUserId = userId);
                showTelegramToast(context,
                    'Switched to individual settings for each account.');
              }
            },
          ),
          // The "Ghost Mode" collapsible mirrors AyuGram's AddCollapsibleToggle /
          // AddInnerToggle (settings_ayu_utils.cpp:228-320, 438-464): the master
          // switch flips all unlocked sub-toggles, while the 5 checkboxes live in
          // an INDEPENDENT SlideWrap disclosure (header arrow + "X/5" badge) that
          // expands/collapses on header-body tap — separate from the master
          // switch — with the shift/long-press lock hint inside the wrap after the
          // checkboxes.
          _GhostModeSection(
            gs: gs,
            settingsKey: key,
            appState: appState,
            isDark: isDark,
            useMaterial: appState.materialSwitches,
            hintColor: subtitleColor,
          ),
          _ToggleRow(
            label: 'Read on Interact',
            value: gs.markReadAfterAction,
            onChanged: (v) {
              gs.markReadAfterAction = v;
              if (v) gs.useScheduledMessages = false;
              appState.ghostSettingChanged(key);
            },
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _DividerText(
            text: 'Automatically marks a message as read when you send a reply, react, or vote in a poll.',
            color: subtitleColor,
          ),
          _ToggleRow(
            label: 'Schedule Messages',
            value: gs.useScheduledMessages,
            onChanged: (v) {
              gs.useScheduledMessages = v;
              if (v) gs.markReadAfterAction = false;
              appState.ghostSettingChanged(key);
            },
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _DividerText(
            text: 'Automatically schedules outgoing messages to send after ~12 seconds. Avoid using on unreliable networks.',
            color: subtitleColor,
          ),
          _SendWithoutSoundRow(
            value: gs.sendWithoutSound,
            onChanged: (v) {
              gs.sendWithoutSound = v;
              appState.ghostSettingChanged(key);
            },
            isDark: isDark,
          ),
          _DividerText(
            text: 'Sends outgoing messages without sound. "In Ghost Mode" only activates when ghost mode is active.',
            color: subtitleColor,
          ),
          _ToggleRow(
            label: 'Suggest Ghost before Story',
            value: gs.suggestGhostModeBeforeViewingStory,
            onChanged: (v) {
              gs.suggestGhostModeBeforeViewingStory = v;
              appState.ghostSettingChanged(key);
            },
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _DividerText(
            text: 'Asks whether to enable ghost mode before viewing a story.',
            color: subtitleColor,
          ),
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Spy essentials (§51.4) ──
          _SectionLabel(label: 'Spy essentials', color: sectionLabelColor),
          _ToggleRow(
            label: 'Save Deleted Messages',
            value: appState.saveDeletedMessages,
            onChanged: (v) => appState.setSaveDeletedMessages(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Save Messages History',
            value: appState.saveMessagesHistory,
            onChanged: (v) => appState.setSaveMessagesHistory(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          Container(height: 1, color: dividerColor, margin: const EdgeInsets.symmetric(horizontal: 22)),
          _ToggleRow(
            label: 'Save for Bots',
            value: appState.saveForBots,
            onChanged: (v) => appState.setSaveForBots(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Other (§54.12) — only localPremium and disableAds per AyuGram ──
          _SectionLabel(label: 'Other', color: sectionLabelColor),
          _ToggleRow(
            label: 'Local Premium',
            value: appState.localPremium,
            onChanged: (v) => appState.setLocalPremium(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Disable Ads',
            value: appState.disableAds,
            onChanged: (v) => appState.setDisableAds(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          const SizedBox(height: 24),
        ];
        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: _lvKids.length,
          itemBuilder: (_, _lvI) => _lvKids[_lvI],
        );
      }),
    );
  }
}

/// The collapsible "Ghost Mode" toggle group — a faithful port of AyuGram's
/// AddCollapsibleToggle + AddInnerToggle (settings_ayu_utils.cpp:228-320,
/// 438-464) as called for Ghost Mode in settings_ayu.cpp:425-430
/// (toggledWhenAll = true, description = the shift/long-press lock hint).
///
/// Two INDEPENDENT controls share the header:
///   • the master switch (`toggleButton->clicks`, :309-320) flips every unlocked
///     sub-toggle on/off — its checked state is the derived `ghostModeActive`;
///   • the SlideWrap disclosure (`button->clicks → wrap->toggle()`, :302-307)
///     expands/collapses the 5 checkboxes and is toggled by tapping the header
///     body. It starts collapsed (`raw->hide(anim::type::instant)`, :454) and is
///     NOT tied to the master state — so a partial ghost config (e.g. ghost
///     everything except online) stays viewable/editable with the master off.
class _GhostModeSection extends StatefulWidget {
  final GhostModeAccountSettings gs;
  final String settingsKey;
  final AppState appState;
  final bool isDark;
  final bool useMaterial;
  final Color hintColor;

  const _GhostModeSection({
    required this.gs,
    required this.settingsKey,
    required this.appState,
    required this.isDark,
    required this.useMaterial,
    required this.hintColor,
  });

  @override
  State<_GhostModeSection> createState() => _GhostModeSectionState();
}

class _GhostModeSectionState extends State<_GhostModeSection> {
  // SlideWrap starts hidden (raw->hide(anim::type::instant),
  // settings_ayu_utils.cpp:454). This disclosure state is independent of the
  // master Ghost Mode switch.
  bool _expanded = false;

  void _toggleMaster() {
    // toggleButton->clicks flips all unlocked inner checks to !checked
    // (settings_ayu_utils.cpp:309-320). setGhostModeEnabledForKey does the same
    // lock-aware flip and (when enabling for the active account) marks online.
    final before = widget.gs.ghostModeActive;
    widget.appState.setGhostModeEnabledForKey(widget.settingsKey, !before);
    final after =
        widget.appState.ensureGhostForKey(widget.settingsKey).ghostModeActive;
    if (before != after) {
      showTelegramToast(context,
          after ? 'Ghost Mode turned on' : 'Ghost Mode turned off');
    }
  }

  @override
  Widget build(BuildContext context) {
    final gs = widget.gs;
    final key = widget.settingsKey;
    final appState = widget.appState;
    final isDark = widget.isDark;
    final textColor = isDark ? Colors.white : Colors.black87;

    // Each row's checkbox `value`, in AyuGram order (settings_ayu.cpp:387-423).
    // The bold "X/Y" badge counts ALL checked sub-toggles, incl. locked ones —
    // countChecked, NOT countUnlockedChecked (settings_ayu_utils.cpp:234).
    final checks = <bool>[
      !gs.sendReadMessages,
      !gs.sendReadStories,
      !gs.sendOnlinePackets,
      !gs.sendUploadProgress,
      gs.sendOfflinePacketAfterOnline,
    ];
    final checkedCount = checks.where((c) => c).length;
    final totalCount = checks.length;

    final rows = <Widget>[
      _LockableToggleRow(
        label: "Don't Read Messages",
        subtitle: 'Block read receipts from being sent',
        value: !gs.sendReadMessages,
        locked: gs.sendReadMessagesLocked,
        onChanged: (v) {
          gs.sendReadMessages = !v;
          appState.ghostSettingChanged(key);
        },
        onLock: () => appState.toggleLockForKey(key, 'sendReadMessages'),
        isDark: isDark,
      ),
      _LockableToggleRow(
        label: "Don't Read Stories",
        subtitle: 'Block story view confirmations',
        value: !gs.sendReadStories,
        locked: gs.sendReadStoriesLocked,
        onChanged: (v) {
          gs.sendReadStories = !v;
          appState.ghostSettingChanged(key);
        },
        onLock: () => appState.toggleLockForKey(key, 'sendReadStories'),
        isDark: isDark,
      ),
      _LockableToggleRow(
        label: "Don't Send Online",
        subtitle: 'Never report online status to the server',
        value: !gs.sendOnlinePackets,
        locked: gs.sendOnlinePacketsLocked,
        onChanged: (v) {
          gs.sendOnlinePackets = !v;
          appState.ghostSettingChanged(key);
        },
        onLock: () => appState.toggleLockForKey(key, 'sendOnlinePackets'),
        isDark: isDark,
      ),
      _LockableToggleRow(
        label: "Don't Send Typing",
        subtitle: 'Block typing and upload progress indicators',
        value: !gs.sendUploadProgress,
        locked: gs.sendUploadProgressLocked,
        onChanged: (v) {
          gs.sendUploadProgress = !v;
          appState.ghostSettingChanged(key);
        },
        onLock: () => appState.toggleLockForKey(key, 'sendUploadProgress'),
        isDark: isDark,
      ),
      _LockableToggleRow(
        label: 'Go Offline Automatically',
        subtitle: 'Immediately go offline after any online appearance',
        value: gs.sendOfflinePacketAfterOnline,
        locked: gs.sendOfflinePacketAfterOnlineLocked,
        onChanged: (v) {
          gs.sendOfflinePacketAfterOnline = v;
          appState.ghostSettingChanged(key);
        },
        onLock: () =>
            appState.toggleLockForKey(key, 'sendOfflinePacketAfterOnline'),
        isDark: isDark,
      ),
      // Lock hint INSIDE the wrap, AFTER the checkboxes — only visible while the
      // section is expanded (settings_ayu_utils.cpp:438-441).
      _DividerText(
        text: 'Shift-click or long-press a toggle to lock it per-account.',
        color: widget.hintColor,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Collapsible header: title + "X/5" badge + arrow ··· master switch ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(
            children: [
              // Tapping the label/arrow body toggles the disclosure (button->
              // clicks → wrap->toggle(), settings_ayu_utils.cpp:302-307). The
              // arrow hugs the right edge of the label text (:279-283).
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Ghost Mode',
                                  style: TextStyle(
                                      fontSize: 14, color: textColor),
                                ),
                                TextSpan(
                                  text: '  $checkedCount/$totalCount',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: textColor),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          // The arrow rotates 180° in sync with the SlideWrap
                          // (slideWrapDuration = 150ms, easeOutCubic) —
                          // settings_ayu_utils.cpp:286-300.
                          turns: _expanded ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOutCubic,
                          child: CustomPaint(
                            size: const Size(20, 20),
                            painter: ExpandArrowPainter(
                                color: context.palette.windowBoldFg),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 1px separator between the body and the toggle (height =
              // 2*border + diameter = 2*2 + 14 = 18), settings_ayu_utils.cpp:170-186.
              Container(width: 1, height: 18, color: context.palette.windowBgOver),
              // Master switch: derived ghostModeActive; tap flips all unlocked
              // sub-toggles. rightsButtonToggleWidth = 70 (boxes.style), flush
              // right so it lines up with the other rows' toggles.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleMaster,
                child: SizedBox(
                  width: 70,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: IgnorePointer(
                      child: AyuToggle(
                        value: gs.ghostModeActive,
                        onChanged: (_) {},
                        isMaterial: widget.useMaterial,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // ── SlideWrap body (height + opacity, easeOutCubic, slideWrapDuration =
        // 150ms) — independent of the master switch (settings_ayu_utils.cpp:286-301).
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _expanded
              ? TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOutCubic,
                  builder: (_, opacity, child) =>
                      Opacity(opacity: opacity, child: child),
                  child: Column(children: rows),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
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

class _DividerText extends StatelessWidget {
  final String text;
  final Color color;
  const _DividerText({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      child: Text(text, style: TextStyle(fontSize: 12, color: color)),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isDark;
  final bool useMaterial;

  const _ToggleRow({
    required this.label,
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
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87)),
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

class _SendWithoutSoundRow extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final bool isDark;

  static const _options = ['Never', 'In Ghost Mode', 'Always'];

  const _SendWithoutSoundRow({
    required this.value,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = isDark
        ? const Color(0xFF6AB2F2)
        : const Color(0xFF3390EC);
    return InkWell(
      onTap: () {
        showSingleChoiceBox(
          context,
          title: 'Send without Sound',
          options: _options,
          initialSelection: value.clamp(0, _options.length - 1),
          onChanged: onChanged,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text('Send without Sound',
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87)),
            ),
            const SizedBox(width: 12),
            Text(
              _options[value.clamp(0, _options.length - 1)],
              style: TextStyle(fontSize: 14, color: accentColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockableToggleRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final bool locked;
  final ValueChanged<bool> onChanged;
  final VoidCallback onLock;
  final bool isDark;

  const _LockableToggleRow({
    required this.label,
    this.subtitle,
    required this.value,
    required this.locked,
    required this.onChanged,
    required this.onLock,
    required this.isDark,
  });

  void _handleTap() {
    if (HardwareKeyboard.instance.isShiftPressed) {
      onLock();
    } else if (!locked) {
      onChanged(!value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLock,
      child: InkWell(
        onTap: _handleTap,
        child: Opacity(
          opacity: locked ? 0.4 : 1.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: value,
                    onChanged: locked ? null : (v) => onChanged(v ?? false),
                    activeColor: context.palette.windowBgActive,
                    side: BorderSide(
                      color: isDark ? const Color(0xFF5A6A78) : const Color(0xFFCBCBCB),
                      width: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(label,
                                style: TextStyle(
                                    fontSize: 14,
                                    color: isDark ? Colors.white : Colors.black87)),
                          ),
                          if (locked) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.lock, size: 14,
                              color: isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999)),
                          ],
                        ],
                      ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GhostEssentialsHeader extends StatelessWidget {
  final Color sectionLabelColor;
  final List<AccountInfo> accounts;
  final bool useGlobal;
  final AccountInfo? activeAccount;
  final void Function(bool global, String? userId) onScopeChanged;

  const _GhostEssentialsHeader({
    required this.sectionLabelColor,
    required this.accounts,
    required this.useGlobal,
    required this.activeAccount,
    required this.onScopeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final showPicker = accounts.length > 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeTextFg = isDark
        ? const Color(0xFF6AB2F2)
        : const Color(0xFF3390EC);

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
      child: Row(
        children: [
          Text('Ghost essentials',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: sectionLabelColor)),
          if (showPicker) ...[
            const SizedBox(width: 8),
            _AccountPickerButton(
              accounts: accounts,
              useGlobal: useGlobal,
              activeAccount: activeAccount,
              activeTextFg: activeTextFg,
              onScopeChanged: onScopeChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountPickerButton extends StatelessWidget {
  final List<AccountInfo> accounts;
  final bool useGlobal;
  final AccountInfo? activeAccount;
  final Color activeTextFg;
  final void Function(bool global, String? userId) onScopeChanged;

  const _AccountPickerButton({
    required this.accounts,
    required this.useGlobal,
    required this.activeAccount,
    required this.activeTextFg,
    required this.onScopeChanged,
  });

  static String accountLabel(AccountInfo a) {
    if (a.displayName.isNotEmpty) return a.displayName;
    if (a.phone.isNotEmpty) return a.phone;
    final platformName = a.platform.isNotEmpty
        ? '${a.platform[0].toUpperCase()}${a.platform.substring(1)}'
        : 'Account';
    final shortId = a.id.length > 8 ? a.id.substring(a.id.length - 8) : a.id;
    return '$platformName ($shortId)';
  }

  String get _currentLabel {
    if (useGlobal) return 'Global';
    if (activeAccount != null) return accountLabel(activeAccount!);
    return 'Account';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _currentLabel,
            style: TextStyle(
              fontSize: 14,
              color: activeTextFg,
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.keyboard_arrow_down,
            size: 18,
            color: activeTextFg,
          ),
        ],
      ),
    );
  }

  void _showPicker(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero);
    final Size buttonSize = button.size;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + buttonSize.height,
        offset.dx + buttonSize.width,
        offset.dy + buttonSize.height,
      ),
      color: isDark ? const Color(0xFF1B2836) : Colors.white,
      items: [
        PopupMenuItem<String>(
          value: 'global',
          child: Row(
            children: [
              _GlobalSettingsAvatar(isActive: useGlobal),
              const SizedBox(width: 10),
              const Text('Global Settings'),
            ],
          ),
        ),
        ...accounts.map((a) => PopupMenuItem<String>(
          value: a.selfUserId,
          child: Row(
            children: [
              _AccountAvatar(account: a, isActive: !useGlobal && a.selfUserId == activeAccount?.selfUserId),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  accountLabel(a),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        )),
      ],
    ).then((value) {
      if (value == null) return;
      if (value == 'global') {
        onScopeChanged(true, null);
      } else {
        onScopeChanged(false, value);
      }
    });
  }
}

class _GlobalSettingsAvatar extends StatelessWidget {
  final bool isActive;
  const _GlobalSettingsAvatar({this.isActive = false});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final innerSize = isActive ? 24.0 : 30.0;
    Widget avatar = Container(
      width: innerSize,
      height: innerSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.peerUserpicBg(4),
            palette.peerUserpicBg2(4),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.visibility_off,
          color: Colors.white,
          size: isActive ? 13.0 : 16.0,
        ),
      ),
    );
    if (!isActive) return avatar;
    return SizedBox(
      width: 30,
      height: 30,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF3390EC),
                width: 2,
              ),
            ),
          ),
          avatar,
        ],
      ),
    );
  }
}

class _AccountAvatar extends StatefulWidget {
  final AccountInfo account;
  final bool isActive;
  const _AccountAvatar({required this.account, this.isActive = false});

  @override
  State<_AccountAvatar> createState() => _AccountAvatarState();
}

class _AccountAvatarState extends State<_AccountAvatar> {
  bool _fileExists = false;

  @override
  void initState() {
    super.initState();
    _checkFile();
  }

  @override
  void didUpdateWidget(_AccountAvatar old) {
    super.didUpdateWidget(old);
    if (old.account.avatarPath != widget.account.avatarPath) {
      _checkFile();
    }
  }

  void _checkFile() {
    if (widget.account.avatarPath.isEmpty) {
      if (_fileExists) setState(() => _fileExists = false);
      return;
    }
    File(widget.account.avatarPath).exists().then((exists) {
      if (mounted && exists != _fileExists) setState(() => _fileExists = exists);
    });
  }

  Widget _wrapWithRing(Widget avatar) {
    if (!widget.isActive) return avatar;
    return SizedBox(
      width: 30,
      height: 30,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF3390EC),
                width: 2,
              ),
            ),
          ),
          avatar,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final innerSize = widget.isActive ? 24.0 : 30.0;
    if (_fileExists) {
      return _wrapWithRing(
        ClipOval(
          child: Image.file(
            File(widget.account.avatarPath),
            width: innerSize,
            height: innerSize,
            fit: BoxFit.cover,
            cacheWidth: 60,
            cacheHeight: 60,
          ),
        ),
      );
    }
    final palette = context.palette;
    final name = _AccountPickerButton.accountLabel(widget.account);
    final initial = name.characters.first.toUpperCase();
    const colorRemap = [0, 7, 4, 1, 6, 3, 5];
    final numId = int.tryParse(widget.account.selfUserId) ?? widget.account.selfUserId.hashCode.abs();
    final avatarColor = palette.peerUserpicBg(colorRemap[numId.abs() % 7]);
    return _wrapWithRing(
      Container(
        width: innerSize,
        height: innerSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: avatarColor,
        ),
        child: Center(
          child: Text(
            initial,
            style: TextStyle(
              color: Colors.white,
              fontSize: widget.isActive ? 11.0 : 13.0,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
