import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../theme/telegram_palette.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../state/app_state.dart';
import 'ayu_section_builder.dart';
import 'ayu_toggle.dart';
import 'confirm_box.dart';

class AyuAppearancePage extends StatelessWidget {
  const AyuAppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final b = AyuSectionBuilder(
        isDark: isDark, useMaterial: appState.materialSwitches);

    b.addSkip();

    b.addSettingToggle(
      label: 'Material Design switches',
      subtitle: 'Use Material-style toggle switches throughout',
      value: appState.materialSwitches,
      onChanged: (v) => appState.setMaterialSwitches(v),
    );

    b.addWidget(_AvatarCornersSection(
      corners: appState.avatarCorners,
      singleCornerRadius: appState.singleCornerRadius,
      onCornersChanged: (v) => appState.setAvatarCorners(v),
      onSingleCornerRadiusChanged: (v) => appState.setSingleCornerRadius(v),
      isDark: isDark,
      useMaterial: appState.materialSwitches,
    ));

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
    if (Platform.isWindows)
      b.addSettingToggle(
        label: 'Hide notification badge',
        subtitle: 'Hides the unread count on the taskbar and tray icon',
        value: appState.hideNotificationBadge,
        onChanged: (v) => appState.setHideNotificationBadge(v),
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
    );
    if (appState.menuBots.isNotEmpty)
      b.addSettingToggle(
        label: 'Bots',
        subtitle: 'Show menu bots in drawer',
        value: appState.showBotsInDrawer,
        onChanged: (v) => appState.setShowBotsInDrawer(v),
      );
    b.addSettingToggle(
      label: 'New Group',
      subtitle: 'Show New Group in drawer',
      value: appState.showNewGroupInDrawer,
      onChanged: (v) => appState.setShowNewGroupInDrawer(v),
    );
    b.addSettingToggle(
      label: 'New Channel',
      subtitle: 'Show New Channel in drawer',
      value: appState.showNewChannelInDrawer,
      onChanged: (v) => appState.setShowNewChannelInDrawer(v),
    );
    b.addSettingToggle(
      label: 'Contacts',
      subtitle: 'Show Contacts in drawer',
      value: appState.showContactsInDrawer,
      onChanged: (v) => appState.setShowContactsInDrawer(v),
    );
    b.addSettingToggle(
      label: 'Calls',
      subtitle: 'Show Calls in drawer',
      value: appState.showCallsInDrawer,
      onChanged: (v) => appState.setShowCallsInDrawer(v),
    );
    b.addSettingToggle(
      label: 'Saved Messages',
      subtitle: 'Show Saved Messages in drawer',
      value: appState.showSavedMessagesInDrawer,
      onChanged: (v) => appState.setShowSavedMessagesInDrawer(v),
    );
    b.addSettingToggle(
      label: 'Night Mode',
      subtitle: 'Show Night Mode toggle in drawer',
      value: appState.showDrawerThemeToggle,
      onChanged: (v) => appState.setShowDrawerThemeToggle(v),
    );
    b.addSettingToggle(
      label: 'Ghost Mode',
      subtitle: 'Show Ghost Mode toggle in drawer',
      value: appState.showGhostToggleInDrawer,
      onChanged: (v) => appState.setShowGhostToggleInDrawer(v),
    );
    b.addSettingToggle(
      label: 'Read Receipts (LRead)',
      subtitle: 'Show Read Receipts toggle in drawer',
      value: appState.showLReadToggleInDrawer,
      onChanged: (v) => appState.setShowLReadToggleInDrawer(v),
    );
    b.addSettingToggle(
      label: 'Story Reads (SRead)',
      subtitle: 'Show Story Reads toggle in drawer',
      value: appState.showSReadToggleInDrawer,
      onChanged: (v) => appState.setShowSReadToggleInDrawer(v),
    );
    if (Platform.isWindows || Platform.isMacOS)
      b.addSettingToggle(
        label: 'Streamer Mode',
        subtitle: 'Show Streamer Mode toggle in drawer',
        value: appState.showStreamerToggleInDrawer,
        onChanged: (v) => appState.setShowStreamerToggleInDrawer(v),
      );

    b.addSectionDivider();

    // App Icon
    b.addSectionTitle('App Icon');
    b.addWidget(_AppIconPicker(
      selectedIcon: appState.appIcon,
      onChanged: (v) => appState.setAppIcon(v),
      isDark: isDark,
    ));

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
              onChanged: (v) => setState(() => _localCorners = v.round()),
              onChangeEnd: (v) {
                final newVal = v.round();
                if (newVal == _committedCorners) return;
                showConfirmBox(
                  context,
                  title: 'Restart Required',
                  text: 'Avatar corners will be applied after restarting.',
                  confirmText: 'Apply',
                  cancelText: 'Cancel',
                  onConfirm: () {
                    _committedCorners = newVal;
                    widget.onCornersChanged(newVal);
                  },
                  onCancel: () =>
                      setState(() => _localCorners = _committedCorners),
                );
              },
            ),
          ),
        ),
        _ToggleRow(
          label: 'Single corner radius',
          subtitle: 'Forums will have the same avatar shape as chats',
          value: widget.singleCornerRadius,
          onChanged: widget.onSingleCornerRadiusChanged,
          isDark: widget.isDark,
          useMaterial: widget.useMaterial,
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
    final bgColor = widget.isDark ? const Color(0xFF24292E) : const Color(0xFFF1F1F1);
    final nameColor = widget.isDark ? Colors.white : Colors.black87;
    final previewColor =
        widget.isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);

    Widget avatarContent;
    if (_userpicBytes != null) {
      avatarContent = Image.memory(
        _userpicBytes!,
        width: photoSize,
        height: photoSize,
        fit: BoxFit.cover,
      );
    } else {
      // EmptyUserpic fallback: colored circle with channel initial
      // Color derived from channel name hash, matching Telegram's palette
      const colors = [
        Color(0xFFE17076), Color(0xFF7BC862), Color(0xFF65AADD),
        Color(0xFFEE7AE6), Color(0xFF6EC9CB), Color(0xFFFAA774),
        Color(0xFFA695E7), Color(0xFFED9B9B),
      ];
      final colorIdx = 'AyuGramReleases'.hashCode.abs() % colors.length;
      avatarContent = Container(
        width: photoSize,
        height: photoSize,
        color: colors[colorIdx],
        alignment: Alignment.center,
        child: const Text('A',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w500)),
      );
    }

    return GestureDetector(
      onTap: () => Process.run('xdg-open', ['https://t.me/AyuGramReleases']),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
        child: Container(
          height: 62,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(avatarRadius),
                child: SizedBox(
                  width: photoSize,
                  height: photoSize,
                  child: avatarContent,
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
                  Text('Monospace font',
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

  static const _presets = [
    '', 'Cascadia Mono', 'JetBrains Mono', 'Fira Code',
    'Source Code Pro', 'Inconsolata', 'Ubuntu Mono', 'Hack',
    'Roboto Mono', 'IBM Plex Mono', 'Cousine',
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
                    final label =
                        font.isEmpty ? 'Default (Cascadia Mono)' : font;
                    return InkWell(
                      onTap: () => setState(() => _controller.text = font),
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
    Color(0xFF40A7E3), Color(0xFF5288C1), Color(0xFF5865F2),
    Color(0xFF1DB954), Color(0xFF6B72D5), Color(0xFF808080),
    Color(0xFFE67E22), Color(0xFFCC3333), Color(0xFF008080),
    Color(0xFFFF69B4), Color(0xFFDA70D6), Color(0xFF4169E1),
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
          childAspectRatio: 1,
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
                        width: 2)
                    : null,
              ),
              child: SizedBox(
                width: 64,
                height: 64,
                child: CustomPaint(
                  painter: _AppIconThemePainter(
                    themeName: name,
                    color: color,
                  ),
                  size: const Size(64, 64),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AppIconThemePainter extends CustomPainter {
  final String themeName;
  final Color color;

  _AppIconThemePainter({required this.themeName, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas.drawRRect(rrect, Paint()..color = color);

    final cx = size.width / 2;
    final cy = size.height / 2;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    switch (themeName) {
      case 'discord':
        _drawDiscord(canvas, cx, cy, size, paint);
      case 'spotify':
        _drawSpotify(canvas, cx, cy, size, strokePaint);
      case 'extera' || 'extera2':
        _drawExtera(canvas, cx, cy, size, paint);
      case 'nothing':
        _drawNothing(canvas, cx, cy, size, strokePaint);
      case 'bard':
        _drawBard(canvas, cx, cy, size, paint);
      case 'yaplus':
        _drawYaPlus(canvas, cx, cy, size, paint, strokePaint);
      case 'win95':
        _drawWin95(canvas, cx, cy, size, paint);
      case 'chibi' || 'chibi2':
        _drawChibi(canvas, cx, cy, size, paint);
      case 'alt':
        _drawAlt(canvas, cx, cy, size, paint);
      default:
        _drawDefault(canvas, cx, cy, size, paint);
    }
  }

  void _drawDefault(Canvas canvas, double cx, double cy, Size size, Paint paint) {
    final s = size.width / 64;
    final path = Path();
    path.moveTo(cx - 18 * s, cy);
    path.lineTo(cx + 16 * s, cy - 14 * s);
    path.lineTo(cx + 16 * s, cy - 4 * s);
    path.lineTo(cx - 6 * s, cy + 14 * s);
    path.close();
    canvas.drawPath(path, paint);
    final path2 = Path();
    path2.moveTo(cx + 16 * s, cy - 4 * s);
    path2.lineTo(cx - 6 * s, cy + 14 * s);
    path2.lineTo(cx - 2 * s, cy + 5 * s);
    path2.lineTo(cx + 6 * s, cy + 10 * s);
    path2.close();
    canvas.drawPath(path2, Paint()..color = Colors.white.withValues(alpha: 0.7));
  }

  void _drawAlt(Canvas canvas, double cx, double cy, Size size, Paint paint) {
    final s = size.width / 64;
    final path = Path();
    path.moveTo(cx + 18 * s, cy);
    path.lineTo(cx - 16 * s, cy - 14 * s);
    path.lineTo(cx - 16 * s, cy - 4 * s);
    path.lineTo(cx + 6 * s, cy + 14 * s);
    path.close();
    canvas.drawPath(path, paint);
    final path2 = Path();
    path2.moveTo(cx - 16 * s, cy - 4 * s);
    path2.lineTo(cx + 6 * s, cy + 14 * s);
    path2.lineTo(cx + 2 * s, cy + 5 * s);
    path2.lineTo(cx - 6 * s, cy + 10 * s);
    path2.close();
    canvas.drawPath(path2, Paint()..color = Colors.white.withValues(alpha: 0.7));
  }

  void _drawDiscord(Canvas canvas, double cx, double cy, Size size, Paint paint) {
    final s = size.width / 64;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 4 * s), width: 28 * s, height: 28 * s),
      paint,
    );
    final band = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy + 12 * s), width: 22 * s, height: 8 * s),
      Radius.circular(4 * s),
    );
    canvas.drawRRect(band, paint);
  }

  void _drawSpotify(Canvas canvas, double cx, double cy, Size size, Paint strokePaint) {
    final s = size.width / 64;
    final sp = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 * s
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 3; i++) {
      final yOff = (i - 1) * 9.0 * s;
      final path = Path();
      path.moveTo(cx - 14 * s, cy + yOff + 3 * s);
      path.quadraticBezierTo(cx, cy + yOff - 6 * s, cx + 14 * s, cy + yOff + 3 * s);
      canvas.drawPath(path, sp);
    }
  }

  void _drawExtera(Canvas canvas, double cx, double cy, Size size, Paint paint) {
    final s = size.width / 64;
    _drawStar(canvas, cx, cy, 14 * s, 6 * s, 4, paint);
    _drawStar(canvas, cx - 12 * s, cy - 10 * s, 6 * s, 3 * s, 4,
        Paint()..color = Colors.white.withValues(alpha: 0.6));
    _drawStar(canvas, cx + 10 * s, cy + 12 * s, 5 * s, 2.5 * s, 4,
        Paint()..color = Colors.white.withValues(alpha: 0.5));
  }

  void _drawStar(Canvas canvas, double cx, double cy, double outer, double inner, int points, Paint paint) {
    final path = Path();
    for (int i = 0; i < points * 2; i++) {
      final angle = (i * 3.14159265 / points) - 3.14159265 / 2;
      final r = i.isEven ? outer : inner;
      final x = cx + r * _cos(angle);
      final y = cy + r * _sin(angle);
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawNothing(Canvas canvas, double cx, double cy, Size size, Paint strokePaint) {
    final s = size.width / 64;
    final sp = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * s;
    canvas.drawCircle(Offset(cx, cy), 16 * s, sp);
    canvas.drawCircle(Offset(cx, cy), 4 * s, Paint()..color = Colors.white);
  }

  void _drawBard(Canvas canvas, double cx, double cy, Size size, Paint paint) {
    final s = size.width / 64;
    _drawStar(canvas, cx, cy, 18 * s, 8 * s, 4, paint);
  }

  void _drawYaPlus(Canvas canvas, double cx, double cy, Size size, Paint paint, Paint strokePaint) {
    final s = size.width / 64;
    final sp = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 14 * s, cy), Offset(cx + 14 * s, cy), sp);
    canvas.drawLine(Offset(cx, cy - 14 * s), Offset(cx, cy + 14 * s), sp);
  }

  void _drawWin95(Canvas canvas, double cx, double cy, Size size, Paint paint) {
    final s = size.width / 64;
    final gap = 2.0 * s;
    final half = 11.0 * s;
    final colors = [
      const Color(0xFFFF0000), const Color(0xFF00FF00),
      const Color(0xFF0000FF), const Color(0xFFFFFF00),
    ];
    final offsets = [
      Offset(cx - half / 2 - gap / 2, cy - half / 2 - gap / 2),
      Offset(cx + gap / 2, cy - half / 2 - gap / 2),
      Offset(cx - half / 2 - gap / 2, cy + gap / 2),
      Offset(cx + gap / 2, cy + gap / 2),
    ];
    for (int i = 0; i < 4; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(offsets[i].dx, offsets[i].dy, half, half),
          Radius.circular(2 * s),
        ),
        Paint()..color = colors[i],
      );
    }
  }

  void _drawChibi(Canvas canvas, double cx, double cy, Size size, Paint paint) {
    final s = size.width / 64;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: 30 * s, height: 32 * s),
      paint,
    );
    final eyePaint = Paint()..color = color;
    canvas.drawCircle(Offset(cx - 6 * s, cy - 3 * s), 3 * s, eyePaint);
    canvas.drawCircle(Offset(cx + 6 * s, cy - 3 * s), 3 * s, eyePaint);
    final smile = Path();
    smile.moveTo(cx - 5 * s, cy + 6 * s);
    smile.quadraticBezierTo(cx, cy + 11 * s, cx + 5 * s, cy + 6 * s);
    canvas.drawPath(smile, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * s
      ..strokeCap = StrokeCap.round);
  }

  static double _cos(double a) => math.cos(a);
  static double _sin(double a) => math.sin(a);

  @override
  bool shouldRepaint(covariant _AppIconThemePainter oldDelegate) =>
      oldDelegate.themeName != themeName || oldDelegate.color != color;
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
