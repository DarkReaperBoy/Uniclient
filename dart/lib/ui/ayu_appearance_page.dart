import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/telegram_palette.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import 'ayu_section_builder.dart';
import 'ayu_toggle.dart';
import '../utils/native_fonts.dart';
import 'package:uniclient/utils/debug.dart';

class AyuAppearancePage extends StatelessWidget {
  const AyuAppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Mirror AyuGram's HasDrawerBots(controller) live query (settings_appearance.cpp:291):
    // pull the active account's main-menu bots so the "Bots" drawer toggle below
    // (gated on appState.menuBots.isNotEmpty) appears when the account has one.
    // Idempotent + post-frame so it never mutates state mid-build.
    final activeAccountId = appState.activeAccountId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appState.ensureMenuBotsLoaded(activeAccountId);
    });

    final b = AyuSectionBuilder(
        isDark: isDark, useMaterial: appState.materialSwitches);

    b.addSkip();

    b.addSectionTitle('App Icon');
    b.addWidget(_AppIconPicker(
      selectedIcon: appState.appIcon,
      onChanged: (v) => appState.setAppIcon(v),
      isDark: isDark,
    ));
    if (Platform.isWindows || Platform.isMacOS) {
      b.addSettingToggle(
        label: 'Hide notification badge',
        value: appState.hideNotificationBadge,
        onChanged: (v) => appState.setHideNotificationBadge(v),
      );
      b.addSkip();
      b.addDividerText(
          'Hides the notification counter on the app icon in the taskbar and tray.');
      b.addSkip();
    } else {
      b.addSectionDivider();
    }

    b.addWidget(_AvatarCornersSection(
      corners: appState.avatarCorners,
      singleCornerRadius: appState.singleCornerRadius,
      onCornersChanged: (v) => appState.setAvatarCorners(v),
      onSingleCornerRadiusChanged: (v) => appState.setSingleCornerRadius(v),
      isDark: isDark,
      useMaterial: appState.materialSwitches,
    ));

    b.addSectionDivider();

    // AyuGram's BuildAppearance opens this group with
    // addSubsectionTitle(tr::ayu_CategoryAppearance()) (settings_appearance.cpp:191)
    // before the MaterialSwitches toggle — match the other groups' titles.
    b.addSectionTitle('Appearance');

    b.addSettingToggle(
      label: 'MD3 Switch Style',
      value: appState.materialSwitches,
      onChanged: (v) => appState.setMaterialSwitches(v),
    );

    b.addSettingToggle(
      label: 'Disable custom backgrounds',
      value: appState.disableCustomBackgrounds,
      onChanged: (v) => appState.setDisableCustomBackgrounds(v),
    );

    b.addSettingToggle(
      label: 'Hide premium statuses',
      value: appState.hidePremiumStatuses,
      onChanged: (v) => appState.setHidePremiumStatuses(v),
    );

    b.addWidget(_MonoFontRow(
      currentFont: appState.monoFont,
      onChanged: (v) => appState.setMonoFont(v),
      isDark: isDark,
    ));

    b.addSectionDivider();

    // Chat Folders
    b.addSectionTitle('Chat Folders');
    b.addSettingToggle(
      label: 'Hide notification counters',
      value: appState.hideNotificationCounters,
      onChanged: (v) => appState.setHideNotificationCounters(v),
    );
    b.addSettingToggle(
      label: 'Hide "All Chats" tab',
      value: appState.hideAllChatsFolder,
      onChanged: (v) => appState.setHideAllChatsFolder(v),
    );

    b.addSectionDivider();

    // Tray Elements (§54.8)
    b.addSectionTitle('Tray Elements');
    b.addSettingToggle(
      label: 'Ghost Mode',
      value: appState.showGhostToggleInTray,
      onChanged: (v) => appState.setShowGhostToggleInTray(v),
    );
    if (Platform.isWindows || Platform.isMacOS)
      b.addSettingToggle(
        label: 'Streamer Mode',
        value: appState.showStreamerToggleInTray,
        onChanged: (v) => appState.setShowStreamerToggleInTray(v),
      );

    b.addSectionDivider();

    // Drawer Elements (§54.8)
    b.addSectionTitle('Drawer Elements');
    b.addSettingToggle(
      label: 'My Profile',
      value: appState.showMyProfileInDrawer,
      onChanged: (v) => appState.setShowMyProfileInDrawer(v),
      icon: Icons.person_outline,
    );
    if (appState.menuBots.isNotEmpty)
      b.addSettingToggle(
        label: 'Bots',
        value: appState.showBotsInDrawer,
        onChanged: (v) => appState.setShowBotsInDrawer(v),
        icon: Icons.smart_toy_outlined,
      );
    b.addSettingToggle(
      label: 'New Group',
      value: appState.showNewGroupInDrawer,
      onChanged: (v) => appState.setShowNewGroupInDrawer(v),
      icon: Icons.group_outlined,
    );
    b.addSettingToggle(
      label: 'New Channel',
      value: appState.showNewChannelInDrawer,
      onChanged: (v) => appState.setShowNewChannelInDrawer(v),
      icon: Icons.campaign_outlined,
    );
    b.addSettingToggle(
      label: 'Contacts',
      value: appState.showContactsInDrawer,
      onChanged: (v) => appState.setShowContactsInDrawer(v),
      icon: Icons.person_add_outlined,
    );
    b.addSettingToggle(
      label: 'Calls',
      value: appState.showCallsInDrawer,
      onChanged: (v) => appState.setShowCallsInDrawer(v),
      icon: Icons.phone_outlined,
    );
    b.addSettingToggle(
      label: 'Saved Messages',
      value: appState.showSavedMessagesInDrawer,
      onChanged: (v) => appState.setShowSavedMessagesInDrawer(v),
      icon: Icons.bookmark_outline,
    );
    b.addSettingToggle(
      label: 'Read on Local',
      value: appState.showLReadToggleInDrawer,
      onChanged: (v) => appState.setShowLReadToggleInDrawer(v),
      icon: Icons.done_all,
    );
    b.addSettingToggle(
      label: 'Read on Server',
      value: appState.showSReadToggleInDrawer,
      onChanged: (v) => appState.setShowSReadToggleInDrawer(v),
      icon: Icons.cloud_done_outlined,
    );
    b.addSettingToggle(
      label: 'Night Mode',
      value: appState.showNightModeToggleInDrawer,
      onChanged: (v) => appState.setShowNightModeToggleInDrawer(v),
      icon: Icons.dark_mode_outlined,
    );
    b.addSettingToggle(
      label: 'Ghost Mode',
      value: appState.showGhostToggleInDrawer,
      onChanged: (v) => appState.setShowGhostToggleInDrawer(v),
      icon: Icons.visibility_off_outlined,
    );
    if (Platform.isWindows || Platform.isMacOS)
      b.addSettingToggle(
        label: 'Streamer Mode',
        value: appState.showStreamerToggleInDrawer,
        onChanged: (v) => appState.setShowStreamerToggleInDrawer(v),
        icon: Icons.live_tv_outlined,
      );

    b.addSkip(24);

    return ayuSettingsScaffold(
      context: context,
      title: 'Appearance',
      children: b.build(),
    );
  }
}

class _AvatarCornersSection extends StatefulWidget {
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

  @override
  State<_AvatarCornersSection> createState() => _AvatarCornersSectionState();
}

class _AvatarCornersSectionState extends State<_AvatarCornersSection> {
  static const _kMax = 23;
  late int _localCorners;
  late int _committedCorners;

  @override
  void initState() {
    super.initState();
    _localCorners = widget.corners;
    _committedCorners = widget.corners;
  }

  @override
  void didUpdateWidget(_AvatarCornersSection old) {
    super.didUpdateWidget(old);
    if (old.corners != widget.corners) {
      _localCorners = widget.corners;
      _committedCorners = widget.corners;
    }
  }

  String get _badgeText {
    if (_localCorners == 0) return 'SQUARE';
    if (_localCorners >= _kMax) return 'CIRCLE';
    return '$_localCorners';
  }

  @override
  Widget build(BuildContext context) {
    final accentColor =
        widget.isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    final textColor = widget.isDark ? Colors.white : Colors.black87;

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.palette.windowBgActive,
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
        _AvatarCornersPreview(corners: _localCorners, isDark: widget.isDark),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: SliderTheme(
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
              value: _localCorners.toDouble(),
              min: 0,
              max: _kMax.toDouble(),
              divisions: _kMax,
              onChanged: (v) {
                setState(() => _localCorners = v.round());
              },
              onChangeEnd: (v) {
                // Applied live — avatars across the app re-clip on the next
                // build (setAvatarCorners → notifyListeners). No restart needed.
                widget.onCornersChanged(v.round());
              },
            ),
          ),
        ),
        _ToggleRow(
          label: 'Single corner radius',
          value: widget.singleCornerRadius,
          onChanged: widget.onSingleCornerRadiusChanged,
          isDark: widget.isDark,
          useMaterial: widget.useMaterial,
        ),
        const SizedBox(height: 7),
        Container(
          height: 1,
          color: widget.isDark
              ? const Color(0xFF101921)
              : const Color(0xFFE0E0E0),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 7, 22, 0),
          child: Text(
              'Forums will have the same avatar shape as chats.',
              style: TextStyle(
                  fontSize: 12,
                  color: widget.isDark
                      ? const Color(0xFF6D7F8F)
                      : const Color(0xFF999999))),
        ),
      ],
    );
  }
}

class _AvatarCornersPreview extends StatefulWidget {
  final int corners;
  final bool isDark;

  const _AvatarCornersPreview({required this.corners, required this.isDark});

  @override
  State<_AvatarCornersPreview> createState() => _AvatarCornersPreviewState();
}

class _AvatarCornersPreviewState extends State<_AvatarCornersPreview> {
  Uint8List? _userpicBytes;
  bool _loading = true;
  String? _channelId;

  @override
  void initState() {
    super.initState();
    _loadUserpic();
  }

  Future<void> _loadUserpic() async {
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final account = appState.activeAccount;
    if (account == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final channelId = await engine.resolveUsername(account.id, 'AyuGramReleases');
      if (channelId == null || !mounted) {
        setState(() => _loading = false);
        return;
      }
      _channelId = channelId;
      final avatarPath = await engine.downloadSingleAvatar(account.id, channelId);
      if (avatarPath == null || !mounted) {
        setState(() => _loading = false);
        return;
      }
      final file = File(avatarPath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (mounted) setState(() { _userpicBytes = bytes; _loading = false; });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const photoSize = 46.0;
    final avatarRadius = photoSize / 2 * (widget.corners / 23.0);
    final bgColor = context.palette.windowBg;
    final nameColor = widget.isDark ? Colors.white : Colors.black87;
    final previewColor =
        widget.isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);

    Widget avatarWidget;
    if (_userpicBytes != null) {
      avatarWidget = ClipRRect(
        borderRadius: BorderRadius.circular(avatarRadius),
        child: Image.memory(
          _userpicBytes!,
          width: photoSize,
          height: photoSize,
          fit: BoxFit.cover,
          cacheWidth: 92,
          cacheHeight: 92,
        ),
      );
    } else {
      // EmptyUserpic fallback for @AyuGramReleases. AyuGram constructs it from
      // Data::DecideColorIndex(peerFromChannel(ChannelId(2331068091))) over the
      // fixed name "AyuGram Releases" (avatar_corners_preview.cpp:29-33):
      //   colorIndex   = 2331068091 % kSimpleColorIndexCount(7) = 2
      //   paletteIndex = ColorIndexToPaletteIndex[2] = 4   (chat_style.cpp:1205)
      //   gradient     = historyPeer5UserpicBg/Bg2 (purple), painted top→bottom
      //   initials     = "AR" (first letter + letter after the space,
      //                  empty_userpic.cpp:656-672)
      // The shape follows AyuUserpic::PaintShape (paintCircle → PaintShape,
      // avatar_corners_preview.cpp:63), i.e. the same avatarRadius as the real
      // userpic — square at corners 0, circle at 23.
      avatarWidget = Container(
        width: photoSize,
        height: photoSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(avatarRadius),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB694F9), Color(0xFF6C61DF)],
          ),
        ),
        child: const Text('AR',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500)),
      );
    }

    // Full-width dialog row. AyuGram adds the preview with horizontal margin 0
    // and only a 2px top margin (settings_appearance.cpp:150-154) and paints an
    // edge-to-edge st::windowBg row with a full-width rectangular ripple
    // (RippleAnimation::RectMask, avatar_corners_preview.cpp:43-90). The avatar
    // sits at the standard 22px settings indent (userpicX = row.padding.left(10)
    // + xShift(12) = 22) and the name/subtitle at nameLeft(68) + xShift(12) = 80
    // (= 22 + photoSize 46 + 12 gap), aligned with every other settings row.
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Material(
        color: bgColor,
        child: InkWell(
          onTap: () async {
            final chatState = context.read<ChatState>();
            final appState = context.read<AppState>();
            final engine = context.read<EngineService>();
            var id = _channelId;
            if (id == null) {
              // Resolve on-demand. AyuGram's mouseReleaseEvent calls
              // showPeerByLink unconditionally (avatar_corners_preview.cpp:93-102),
              // resolving the username then navigating regardless of any prior
              // failed/in-flight resolution — so a null channel must not no-op.
              try {
                final account = appState.activeAccount;
                if (account != null) {
                  id = await engine.resolveUsername(
                      account.id, 'AyuGramReleases');
                  if (mounted && id != null) {
                    setState(() => _channelId = id);
                  }
                }
              } catch (e) {
                Debug.log('ayu_appearance_page', 'final account = appState.activeAccount: $e');
              }
            }
            if (id != null && mounted) {
              chatState.openChatById(id);
            }
          },
          child: SizedBox(
            height: 62,
            child: Padding(
              padding: const EdgeInsets.only(left: 22, right: 22),
              child: Row(
                children: [
                  SizedBox(
                    width: photoSize,
                    height: photoSize,
                    child: avatarWidget,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text('AyuGram Releases',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: nameColor),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 3),
                            Icon(Icons.verified,
                                size: 15,
                                color: widget.isDark
                                    ? const Color(0xFF6AB2F2)
                                    : const Color(0xFF3390EC)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Better late than never',
                            style: TextStyle(fontSize: 13, color: previewColor),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
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
                  Text('Monospace Font',
                      style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87)),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Font for code and pre blocks',
                        style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? const Color(0xFF6D7F8F)
                                : const Color(0xFF999999))),
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
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  String _searchQuery = '';
  List<String> _systemFonts = [];
  bool _loadingFonts = true;
  late String _selectedFont;
  List<String>? _cachedFilteredFonts;
  String _cachedFilterQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedFont = widget.currentFont;
    _controller = TextEditingController(text: widget.currentFont);
    _loadSystemFonts();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final fonts = _filteredFonts;
    if (fonts.isEmpty) return KeyEventResult.ignored;
    final idx = fonts.indexOf(_selectedFont);
    int newIdx = idx;
    const pageSize = 10;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      newIdx = (idx + 1).clamp(0, fonts.length - 1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      newIdx = (idx - 1).clamp(0, fonts.length - 1);
    } else if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      newIdx = (idx + pageSize).clamp(0, fonts.length - 1);
    } else if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      newIdx = (idx - pageSize).clamp(0, fonts.length - 1);
    } else {
      return KeyEventResult.ignored;
    }

    if (newIdx != idx) {
      setState(() {
        _selectedFont = fonts[newIdx];
        _controller.text = _selectedFont;
      });
      _scrollToIndex(newIdx);
    }
    return KeyEventResult.handled;
  }

  // Enter selects the highlighted font. AyuGram wires the search field's submit
  // to Content::activateBySubmit (font_selector.cpp:928 → :816): if nothing is
  // selected it jumps to the first row, then activates it — setting the pending
  // font (committed only on Save/OK). It does NOT close the box.
  void _activateBySubmit() {
    final fonts = _filteredFonts;
    if (fonts.isEmpty) return;
    var idx = fonts.indexOf(_selectedFont);
    if (idx < 0) idx = 0; // jump(1): first row when the selection isn't in view
    if (_selectedFont != fonts[idx]) {
      setState(() {
        _selectedFont = fonts[idx];
        _controller.text = _selectedFont;
      });
    }
    _scrollToIndex(idx);
  }

  // Minimal scroll to keep the selected row visible, mirroring AyuGram's
  // scrollToY(ymin, ymax) which scrolls only when the row is off-screen
  // (font_selector.cpp:986-988) rather than snapping it to the top.
  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    const rowHeight = 32.0;
    final itemTop = index * rowHeight;
    final itemBottom = itemTop + rowHeight;
    final pos = _scrollController.position;
    final current = pos.pixels;
    final viewport = pos.viewportDimension;
    double target = current;
    if (itemTop < current) {
      target = itemTop;
    } else if (itemBottom > current + viewport) {
      target = itemBottom - viewport;
    }
    target = target.clamp(0.0, pos.maxScrollExtent);
    if ((target - current).abs() > 0.5) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _loadSystemFonts() async {
    // System fonts come from the `system_fonts` plugin (platform channels) via
    // NativeFonts — no `fc-list` / `osascript` / `powershell` subprocess. The
    // result is already de-duplicated and sorted; the helper never throws.
    final fonts = NativeFonts.list();
    if (fonts.isNotEmpty) {
      if (mounted) setState(() { _systemFonts = ['', ...fonts]; _loadingFonts = false; _cachedFilteredFonts = null; });
    } else if (mounted) {
      setState(() {
        _systemFonts = [''];
        _loadingFonts = false;
        _cachedFilteredFonts = null;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<String> get _filteredFonts {
    if (_searchQuery.isEmpty) return _systemFonts;
    if (_cachedFilteredFonts != null && _cachedFilterQuery == _searchQuery) {
      return _cachedFilteredFonts!;
    }
    _cachedFilterQuery = _searchQuery;
    final needles = _searchQuery.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    _cachedFilteredFonts = _systemFonts
        .where((f) {
          final haystack = f.isEmpty ? 'default' : f.toLowerCase();
          final words = haystack.split(RegExp(r'[\s\-_]+'));
          return needles.every((needle) =>
              words.any((w) => w.startsWith(needle)));
        })
        .toList();
    return _cachedFilteredFonts!;
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
    final fonts = _filteredFonts;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: 320,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          // Global key interceptor: AyuGram's keyPressEvent is on the BOX
          // (font_selector.cpp:967), so arrow/page navigation works even while
          // the autofocus search field holds primary focus — the field doesn't
          // consume arrow/page keys, so they bubble up to this non-focusable
          // ancestor Focus. The old Focus wrapped only the ListView and never
          // saw a key while the field was focused, so _onKeyEvent was dead.
          child: Focus(
            canRequestFocus: false,
            onKeyEvent: _onKeyEvent,
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Customize Font',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor)),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(fontSize: 14, color: textColor),
                decoration: InputDecoration(
                  hintText: 'Search fonts...',
                  hintStyle: TextStyle(fontSize: 14, color: subtitleColor),
                  prefixIcon: Icon(Icons.search, size: 18, color: subtitleColor),
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
                onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                // Enter activates the highlighted font (AyuGram MultiSelect
                // setSubmittedCallback → activateBySubmit, font_selector.cpp:928).
                onSubmitted: (_) => _activateBySubmit(),
              ),
              const SizedBox(height: 12),
              if (_loadingFonts)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (fonts.isEmpty)
                // font_selector.cpp:696-717: when the filtered list is empty the
                // rows are hidden and a centered "No fonts found." FlatLabel
                // (st::membersAbout) is shown in its place.
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text('No fonts found.',
                        style: TextStyle(fontSize: 14, color: subtitleColor)),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    controller: _scrollController,
                    shrinkWrap: true,
                    itemCount: fonts.length,
                    itemBuilder: (ctx, i) {
                      final font = fonts[i];
                      final isSelected = _selectedFont == font;
                      final label =
                          font.isEmpty ? 'Default' : font;
                      return InkWell(
                        onTap: () => setState(() {
                          _selectedFont = font;
                          _controller.text = font;
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontFamily:
                                          font.isEmpty ? 'monospace' : font,
                                      color:
                                          isSelected ? accentColor : textColor,
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
                children: [
                  TextButton(
                    onPressed: _reset,
                    child: Text('Reset',
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
      ),
    );
  }

  void _save() {
    // Applied live — the app theme rebuilds with the new fontFamily
    // (customFontFamily → notifyListeners → AppTheme.fromPalette). No restart.
    if (_selectedFont != widget.currentFont) {
      widget.onSaved(_selectedFont);
    }
    Navigator.of(context).pop();
  }

  void _reset() {
    if (widget.currentFont.isNotEmpty) {
      widget.onSaved('');
    }
    Navigator.of(context).pop();
  }
}

class _AppIconPicker extends StatefulWidget {
  final String selectedIcon;
  final ValueChanged<String> onChanged;
  final bool isDark;

  const _AppIconPicker({
    required this.selectedIcon,
    required this.onChanged,
    required this.isDark,
  });

  static const icons = [
    'default', 'alt', 'discord', 'spotify', 'extera', 'nothing',
    'bard', 'yaplus', 'win95', 'chibi', 'chibi2', 'extera2',
  ];

  @override
  State<_AppIconPicker> createState() => _AppIconPickerState();
}

class _AppIconPickerState extends State<_AppIconPicker> {
  String? _prevSelected;

  String get _selected =>
      widget.selectedIcon.isEmpty ? 'default' : widget.selectedIcon;

  @override
  Widget build(BuildContext context) {
    final dividerBg = context.palette.boxDividerBg;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1,
        ),
        itemCount: _AppIconPicker.icons.length,
        itemBuilder: (ctx, i) {
          final name = _AppIconPicker.icons[i];
          final isSelected = name == _selected;
          final wasPrev = name == _prevSelected;
          return GestureDetector(
            onTap: () {
              if (name == _selected) return;
              setState(() => _prevSelected = _selected);
              final newIcon = name == 'default' ? '' : name;
              widget.onChanged(newIcon);
              // Apply live at the click site — mirrors AyuGram applyIcon()
              // (icon_picker.cpp:42), which refreshes the window-frame + tray
              // icon immediately before persisting so the change shows without a
              // restart. main.dart's appIcon listener also applies it via
              // setAppIcon→notifyListeners; this co-located call matches AyuGram
              // and drives the native updateAppIcon handler directly
              // (linux/my_application.cc:432 → gtk_window_set_icon + tray icon).
              () async {
                try {
                  await const MethodChannel('com.uniclient.app/tray')
                      .invokeMethod('updateAppIcon',
                          {'icon': newIcon.isEmpty ? 'default' : newIcon});
                } catch (e) {
                  Debug.log('ayu_appearance_page', 'await const MethodChannel(\'com.uniclient.app/tray\'): $e');
                }
              }();
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedOpacity(
                  opacity: isSelected ? 1.0 : 0.0,
                  duration: Duration(milliseconds: (isSelected || wasPrev) ? 200 : 0),
                  curve: Curves.easeOutCubic,
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: dividerBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Center(
                  child: Image.asset(
                    'assets/icons/ayu/$name.png',
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 64,
                      height: 64,
                      color: const Color(0xFF40A7E3),
                      child: const Icon(Icons.apps,
                          color: Colors.white, size: 24),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
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
