import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    final accentColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    final textColor = isDark ? Colors.white : Colors.black87;

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
                  color: isDark
                      ? const Color(0xFF5288C1)
                      : const Color(0xFF40A7E3),
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
              inactiveTrackColor:
                  isDark ? const Color(0xFF2B3C4C) : const Color(0xFFD5D5D5),
              thumbColor: accentColor,
              overlayColor: const Color(0x2940A7E3),
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 7.5),
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
    final previewColor =
        isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);

    return Padding(
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
