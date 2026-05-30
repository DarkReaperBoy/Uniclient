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

class AyuAppearancePage extends StatelessWidget {
  const AyuAppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

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

    b.addSettingToggle(
      label: 'MD3 Switch Style',
      subtitle: 'Use Material-style toggle switches throughout',
      value: appState.materialSwitches,
      onChanged: (v) => appState.setMaterialSwitches(v),
    );

    b.addSettingToggle(
      label: 'Disable custom backgrounds',
      subtitle: 'Force global wallpaper on all chats',
      value: appState.disableCustomBackgrounds,
      onChanged: (v) => appState.setDisableCustomBackgrounds(v),
    );

    b.addSettingToggle(
      label: 'Hide premium statuses',
      subtitle: 'Hide emoji status badges next to usernames',
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
      subtitle: 'Hide unread count badges on folder tabs',
      value: appState.hideNotificationCounters,
      onChanged: (v) => appState.setHideNotificationCounters(v),
    );
    b.addSettingToggle(
      label: 'Hide "All Chats" tab',
      subtitle: 'Remove the All Chats folder tab from the folder bar',
      value: appState.hideAllChatsFolder,
      onChanged: (v) => appState.setHideAllChatsFolder(v),
    );

    b.addSectionDivider();

    // Tray Elements (§54.8)
    b.addSectionTitle('Tray Elements');
    b.addSettingToggle(
      label: 'Ghost Mode',
      subtitle: 'Show Ghost Mode toggle in system tray menu',
      value: appState.showGhostToggleInTray,
      onChanged: (v) => appState.setShowGhostToggleInTray(v),
    );
    if (Platform.isWindows || Platform.isMacOS)
      b.addSettingToggle(
        label: 'Streamer Mode',
        subtitle: 'Show Streamer Mode toggle in system tray menu',
        value: appState.showStreamerToggleInTray,
        onChanged: (v) => appState.setShowStreamerToggleInTray(v),
      );

    b.addSectionDivider();

    // Drawer Elements (§54.8)
    b.addSectionTitle('Drawer Elements');
    b.addSettingToggle(
      label: 'My Profile',
      subtitle: 'Show My Profile in drawer',
      value: appState.showMyProfileInDrawer,
      onChanged: (v) => appState.setShowMyProfileInDrawer(v),
      icon: Icons.person_outline,
    );
    if (appState.menuBots.isNotEmpty)
      b.addSettingToggle(
        label: 'Bots',
        subtitle: 'Show menu bots in drawer',
        value: appState.showBotsInDrawer,
        onChanged: (v) => appState.setShowBotsInDrawer(v),
        icon: Icons.smart_toy_outlined,
      );
    b.addSettingToggle(
      label: 'New Group',
      subtitle: 'Show New Group in drawer',
      value: appState.showNewGroupInDrawer,
      onChanged: (v) => appState.setShowNewGroupInDrawer(v),
      icon: Icons.group_outlined,
    );
    b.addSettingToggle(
      label: 'New Channel',
      subtitle: 'Show New Channel in drawer',
      value: appState.showNewChannelInDrawer,
      onChanged: (v) => appState.setShowNewChannelInDrawer(v),
      icon: Icons.campaign_outlined,
    );
    b.addSettingToggle(
      label: 'Contacts',
      subtitle: 'Show Contacts in drawer',
      value: appState.showContactsInDrawer,
      onChanged: (v) => appState.setShowContactsInDrawer(v),
      icon: Icons.person_add_outlined,
    );
    b.addSettingToggle(
      label: 'Calls',
      subtitle: 'Show Calls in drawer',
      value: appState.showCallsInDrawer,
      onChanged: (v) => appState.setShowCallsInDrawer(v),
      icon: Icons.phone_outlined,
    );
    b.addSettingToggle(
      label: 'Saved Messages',
      subtitle: 'Show Saved Messages in drawer',
      value: appState.showSavedMessagesInDrawer,
      onChanged: (v) => appState.setShowSavedMessagesInDrawer(v),
      icon: Icons.bookmark_outline,
    );
    b.addSettingToggle(
      label: 'Read on Local',
      subtitle: 'Show Read on Local toggle in drawer',
      value: appState.showLReadToggleInDrawer,
      onChanged: (v) => appState.setShowLReadToggleInDrawer(v),
      icon: Icons.done_all,
    );
    b.addSettingToggle(
      label: 'Read on Server',
      subtitle: 'Show Read on Server toggle in drawer',
      value: appState.showSReadToggleInDrawer,
      onChanged: (v) => appState.setShowSReadToggleInDrawer(v),
      icon: Icons.cloud_done_outlined,
    );
    b.addSettingToggle(
      label: 'Night Mode',
      subtitle: 'Show Night Mode toggle in drawer',
      value: appState.showNightModeToggleInDrawer,
      onChanged: (v) => appState.setShowNightModeToggleInDrawer(v),
      icon: Icons.dark_mode_outlined,
    );
    b.addSettingToggle(
      label: 'Ghost Mode',
      subtitle: 'Show Ghost Mode toggle in drawer',
      value: appState.showGhostToggleInDrawer,
      onChanged: (v) => appState.setShowGhostToggleInDrawer(v),
      icon: Icons.visibility_off_outlined,
    );
    if (Platform.isWindows || Platform.isMacOS)
      b.addSettingToggle(
        label: 'Streamer Mode',
        subtitle: 'Show Streamer Mode toggle in drawer',
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

  void _showRestartDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restart Required'),
        content: const Text(
            'The avatar corners change will be applied after restarting the app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Restart Later', style: TextStyle(color: accentColor)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.read<AppState>().flushSettingsSync();
              final exe = Platform.resolvedExecutable;
              Process.start(exe, Platform.executableArguments,
                  mode: ProcessStartMode.detached).then((_) {
                exit(0);
              }).catchError((_) {
                exit(0);
              });
            },
            child: Text('Restart Now',
                style: TextStyle(
                    color: accentColor, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
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
                final newVal = v.round();
                widget.onCornersChanged(newVal);
                if (newVal == _committedCorners) return;
                _committedCorners = newVal;
                _showRestartDialog(context);
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
      const colors = [
        Color(0xFFE17076), Color(0xFF7BC862), Color(0xFF65AADD),
        Color(0xFFEE7AE6), Color(0xFF6EC9CB), Color(0xFFFAA774),
        Color(0xFFA695E7), Color(0xFFED9B9B),
      ];
      final colorIdx = 'AyuGramReleases'.hashCode.abs() % colors.length;
      avatarWidget = ClipRRect(
        borderRadius: BorderRadius.circular(avatarRadius),
        child: Container(
          width: photoSize,
          height: photoSize,
          color: colors[colorIdx],
          alignment: Alignment.center,
          child: const Text('A',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w500)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
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
              } catch (_) {
                // resolve failed — nothing to open
              }
            }
            if (id != null && mounted) {
              chatState.openChatById(id);
            }
          },
          child: Container(
            height: 62,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
  final _listFocusNode = FocusNode();
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
      final offset = newIdx * 32.0;
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
    return KeyEventResult.handled;
  }

  Future<void> _loadSystemFonts() async {
    List<String>? families;
    try {
      if (Platform.isLinux || Platform.isMacOS) {
        families = await _loadViaFcList();
      }
      if (families == null && Platform.isMacOS) {
        families = await _loadViaMacOSFontManager();
      }
      if (families == null && Platform.isWindows) {
        families = await _loadViaWindowsPowerShell();
      }
      if (families == null && (Platform.isAndroid || Platform.isIOS)) {
        families = await _loadViaMobileFontDir();
      }
    } catch (_) {}
    if (families != null && families.isNotEmpty) {
      if (mounted) setState(() { _systemFonts = ['', ...families!]; _loadingFonts = false; _cachedFilteredFonts = null; });
    } else if (mounted) {
      setState(() {
        _systemFonts = [''];
        _loadingFonts = false;
        _cachedFilteredFonts = null;
      });
    }
  }

  Future<List<String>?> _loadViaFcList() async {
    try {
      final result = await Process.run('fc-list', ['-f', '%{family}\n']);
      if (result.exitCode == 0) {
        final families = <String>{};
        for (final line in (result.stdout as String).split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) {
            for (final family in trimmed.split(',')) {
              final f = family.trim();
              if (f.isNotEmpty) families.add(f);
            }
          }
        }
        if (families.isNotEmpty) {
          return families.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<String>?> _loadViaMacOSFontManager() async {
    try {
      final result = await Process.run('osascript', [
        '-l', 'JavaScript',
        '-e',
        'ObjC.import("AppKit");'
        'var fm = \$.NSFontManager.sharedFontManager;'
        'var arr = fm.availableFontFamilies;'
        'var out = [];'
        'for (var i = 0; i < arr.count; i++) out.push(arr.objectAtIndex(i).js);'
        'out.sort(function(a,b){return a.toLowerCase().localeCompare(b.toLowerCase())});'
        'out.join("\\n");',
      ]);
      if (result.exitCode == 0) {
        final families = <String>{};
        for (final line in (result.stdout as String).split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) families.add(trimmed);
        }
        if (families.isNotEmpty) {
          return families.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<String>?> _loadViaWindowsPowerShell() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile', '-Command',
        'Add-Type -AssemblyName System.Drawing; '
            '(New-Object System.Drawing.Text.InstalledFontCollection).Families '
            '| ForEach-Object { \$_.Name }',
      ]);
      if (result.exitCode == 0) {
        final families = <String>{};
        for (final line in (result.stdout as String).split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) families.add(trimmed);
        }
        if (families.isNotEmpty) {
          return families.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<String>?> _loadViaMobileFontDir() async {
    final families = <String>{};
    final fontDirs = Platform.isAndroid
        ? ['/system/fonts', '/system/font']
        : ['/System/Library/Fonts', '/Library/Fonts'];
    for (final dirPath in fontDirs) {
      try {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;
        await for (final entity in dir.list()) {
          if (entity is! File) continue;
          final name = entity.uri.pathSegments.last;
          if (!name.endsWith('.ttf') && !name.endsWith('.otf') && !name.endsWith('.ttc')) continue;
          var family = name.replaceAll(RegExp(r'\.(ttf|otf|ttc)$'), '');
          family = family.replaceAll(RegExp(r'-(Regular|Bold|Italic|Light|Medium|Thin|Black|SemiBold|ExtraBold|ExtraLight|BoldItalic|LightItalic|MediumItalic)$'), '');
          family = family.replaceAll(RegExp(r'_'), ' ');
          if (family.isNotEmpty) families.add(family);
        }
      } catch (_) {}
    }
    if (families.isNotEmpty) {
      return families.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
    return null;
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _listFocusNode.dispose();
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
              ),
              const SizedBox(height: 12),
              if (_loadingFonts)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                Focus(
                  focusNode: _listFocusNode,
                  onKeyEvent: _onKeyEvent,
                  child: ConstrainedBox(
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
    );
  }

  void _showRestartDialog(String fontValue) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restart Required'),
        content: const Text('The font change will be applied after restarting the app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Restart Later', style: TextStyle(color: accentColor)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.read<AppState>().flushSettingsSync();
              final exe = Platform.resolvedExecutable;
              Process.start(exe, Platform.executableArguments,
                  mode: ProcessStartMode.detached).then((_) {
                exit(0);
              }).catchError((_) {
                exit(0);
              });
            },
            child: Text('Restart Now',
                style: TextStyle(
                    color: accentColor, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _save() {
    final newFont = _selectedFont;
    if (newFont != widget.currentFont) {
      widget.onSaved(newFont);
      Navigator.of(context).pop();
      _showRestartDialog(newFont);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _reset() {
    if (widget.currentFont.isNotEmpty) {
      widget.onSaved('');
      Navigator.of(context).pop();
      _showRestartDialog('');
    } else {
      Navigator.of(context).pop();
    }
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
                } catch (_) {
                  // native tray plugin unavailable (e.g. non-Linux) — ignore
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
                      child: const Icon(Icons.image_not_supported,
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
