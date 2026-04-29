import 'package:flutter/material.dart';

const double _exportPanelWidth = 364;
const double _exportPanelHeight = 480;
const double _boxRadius = 8;
const double _titleBarHeight = 48;

enum ExportMode { full, perChat, perTopic }

enum ExportPhase { settings, processing, completed, error }

class ExportTarget {
  final ExportMode mode;
  final String? accountId;
  final String? chatId;
  final String? chatTitle;
  final int? topicRootId;
  final String? topicTitle;

  const ExportTarget({
    required this.mode,
    this.accountId,
    this.chatId,
    this.chatTitle,
    this.topicRootId,
    this.topicTitle,
  });

  String get settingsTitle {
    switch (mode) {
      case ExportMode.full:
        return 'Export Your Data';
      case ExportMode.perChat:
        return 'Export Chat History';
      case ExportMode.perTopic:
        return 'Export Topic History';
    }
  }

  String get panelTitle => settingsTitle;
}

void showExportPanel(BuildContext context, ExportTarget target) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ExportPanelDialog(target: target),
  );
}

void showExportSuggestBox(BuildContext context, {VoidCallback? onStart}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ExportSuggestBox(onStart: onStart),
  );
}

class _ExportPanelDialog extends StatefulWidget {
  final ExportTarget target;

  const _ExportPanelDialog({required this.target});

  @override
  State<_ExportPanelDialog> createState() => _ExportPanelDialogState();
}

enum _ExportFormat { html, json, htmlAndJson }

class _ExportPanelDialogState extends State<_ExportPanelDialog>
    with WidgetsBindingObserver {
  ExportPhase _phase = ExportPhase.settings;

  // Account data
  bool _personalInfo = true;
  bool _contacts = true;
  bool _stories = true;
  bool _profileMusic = true;

  // Chat types
  bool _personalChats = true;
  bool _botChats = false;
  bool _privateGroups = true;
  bool _privateChannels = false;
  bool _publicGroups = false;
  bool _publicChannels = false;

  // "Only my messages" sub-options
  bool _privateGroupsOnlyMy = false;
  bool _privateChannelsOnlyMy = false;
  bool _publicGroupsOnlyMy = true; // forced on
  bool _publicChannelsOnlyMy = true; // forced on

  // Media types
  bool _mediaPhotos = true;
  bool _mediaVideo = false;
  bool _mediaVoice = false;
  bool _mediaVideoMessage = false;
  bool _mediaSticker = false;
  bool _mediaGif = false;
  bool _mediaFile = false;

  // Size limit: slider position 0..99 (default index 7 = 8MB)
  double _sizeSliderPos = 7;

  // Other data
  bool _sessions = false;
  bool _otherData = false;

  // Output format
  _ExportFormat _format = _ExportFormat.html;

  // Scroll state for fade shadows
  final ScrollController _scrollController = ScrollController();
  bool _showTopShadow = false;
  bool _showBottomShadow = true;

  String get _title {
    switch (_phase) {
      case ExportPhase.processing:
        return 'Exporting Data...';
      case ExportPhase.completed:
      case ExportPhase.error:
        return widget.target.settingsTitle;
      case ExportPhase.settings:
        return widget.target.settingsTitle;
    }
  }

  bool get _hideOnDeactivate => _phase == ExportPhase.processing;

  bool get _anyChatSelected =>
      _personalChats ||
      _botChats ||
      _privateGroups ||
      _privateChannels ||
      _publicGroups ||
      _publicChannels;

  bool get _showMediaSection => _anyChatSelected || _profileMusic;

  bool get _anyTypeSelected =>
      _personalInfo ||
      _contacts ||
      _stories ||
      _profileMusic ||
      _anyChatSelected ||
      _sessions ||
      _otherData;

  int get _sizeLimitMB {
    final i = _sizeSliderPos.round() + 1;
    if (i <= 10) return i;
    if (i <= 30) return 10 + (i - 10) * 2;
    if (i <= 40) return 50 + (i - 30) * 5;
    if (i <= 60) return 100 + (i - 40) * 10;
    if (i <= 70) return 300 + (i - 60) * 20;
    if (i <= 80) return 500 + (i - 70) * 50;
    if (i <= 90) return 1000 + (i - 80) * 100;
    return 2000 + (i - 90) * 200;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_updateShadows);
  }

  void _updateShadows() {
    final pos = _scrollController.position;
    final newTop = pos.pixels > 0;
    final newBottom = pos.pixels < pos.maxScrollExtent;
    if (newTop != _showTopShadow || newBottom != _showBottomShadow) {
      setState(() {
        _showTopShadow = newTop;
        _showBottomShadow = newBottom;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_hideOnDeactivate && state == AppLifecycleState.inactive) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleClose() async {
    if (_phase == ExportPhase.processing) {
      final confirmed = await _showStopConfirmation();
      if (confirmed && mounted) {
        Navigator.of(context).pop();
      }
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<bool> _showStopConfirmation() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final boxBg = isDark ? const Color(0xFF17212B) : Colors.white;
    final boxTextFg =
        isDark ? const Color(0xFFAAAAAA) : const Color(0xFF000000);
    final attentionFg =
        isDark ? const Color(0xFFEC3942) : const Color(0xFFD14E4E);
    final cancelFg =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: boxBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
        ),
        elevation: 4,
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
                child: Text(
                  'Are you sure you want to stop exporting your data?',
                  style: TextStyle(
                    fontSize: 14,
                    height: 22 / 14,
                    color: boxTextFg,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 12, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: cancelFg,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: TextButton.styleFrom(
                        foregroundColor: attentionFg,
                        overlayColor: attentionFg.withValues(alpha: 0.1),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: const Text('Stop'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  @visibleForTesting
  void setPhase(ExportPhase phase) {
    setState(() => _phase = phase);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final titleColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final borderColor =
        isDark ? const Color(0xFF0E1621) : const Color(0xFFE0E0E0);

    return PopScope(
      canPop: _phase != ExportPhase.processing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleClose();
      },
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: _exportPanelWidth,
            height: _exportPanelHeight,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(_boxRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_boxRadius),
              child: Column(
                children: [
                  _buildTitleBar(
                      titleColor, subtextColor, borderColor),
                  Expanded(
                    child: _buildContent(subtextColor),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar(
      Color titleColor, Color subtextColor, Color borderColor) {
    return Container(
      height: _titleBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: borderColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: titleColor,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 20, color: subtextColor),
            onPressed: _handleClose,
            splashRadius: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(Color subtextColor) {
    switch (_phase) {
      case ExportPhase.settings:
        return _buildFullExportSettings(subtextColor);
      case ExportPhase.processing:
        return _buildProcessingPlaceholder(subtextColor);
      case ExportPhase.completed:
        return _buildCompletedPlaceholder(subtextColor);
      case ExportPhase.error:
        return _buildErrorPlaceholder(subtextColor);
    }
  }

  Widget _buildFullExportSettings(Color subtextColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final headerColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final shadowColor =
        isDark ? const Color(0xFF0E1621) : const Color(0xFFE0E0E0);

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              ListView(
                controller: _scrollController,
                padding: EdgeInsets.zero,
                children: [
                  // §29.3.1 Account Data (no header)
                  _buildOptionWithAbout(
                    'Personal information',
                    'Exports profile photos, name, bio, etc.',
                    _personalInfo,
                    (v) => setState(() => _personalInfo = v!),
                    textColor,
                    subtextColor,
                  ),
                  _buildOptionWithAbout(
                    'Contact list',
                    'Exports names and phone numbers.',
                    _contacts,
                    (v) => setState(() => _contacts = v!),
                    textColor,
                    subtextColor,
                  ),
                  _buildOptionWithAbout(
                    'Stories',
                    'Exports your stories.',
                    _stories,
                    (v) => setState(() => _stories = v!),
                    textColor,
                    subtextColor,
                  ),
                  _buildOptionWithAbout(
                    'Profile music',
                    'Exports your profile music.',
                    _profileMusic,
                    (v) => setState(() => _profileMusic = v!),
                    textColor,
                    subtextColor,
                  ),

                  // §29.3.2 Chats section
                  _buildSectionHeader('Chats', headerColor),
                  _buildChatTypeOption(
                    'Personal chats',
                    _personalChats,
                    (v) => setState(() => _personalChats = v!),
                    textColor,
                    hasSubOption: false,
                  ),
                  _buildChatTypeOption(
                    'Bot chats',
                    _botChats,
                    (v) => setState(() => _botChats = v!),
                    textColor,
                    hasSubOption: false,
                  ),
                  _buildChatTypeOption(
                    'Private groups',
                    _privateGroups,
                    (v) => setState(() => _privateGroups = v!),
                    textColor,
                    hasSubOption: true,
                    subChecked: _privateGroupsOnlyMy,
                    subEnabled: true,
                    onSubChanged: (v) =>
                        setState(() => _privateGroupsOnlyMy = v!),
                    parentChecked: _privateGroups,
                  ),
                  _buildChatTypeOption(
                    'Private channels',
                    _privateChannels,
                    (v) => setState(() => _privateChannels = v!),
                    textColor,
                    hasSubOption: true,
                    subChecked: _privateChannelsOnlyMy,
                    subEnabled: true,
                    onSubChanged: (v) =>
                        setState(() => _privateChannelsOnlyMy = v!),
                    parentChecked: _privateChannels,
                  ),
                  _buildChatTypeOption(
                    'Public groups',
                    _publicGroups,
                    (v) => setState(() => _publicGroups = v!),
                    textColor,
                    hasSubOption: true,
                    subChecked: _publicGroupsOnlyMy,
                    subEnabled: false, // forced on, disabled
                    onSubChanged: null,
                    parentChecked: _publicGroups,
                  ),
                  _buildChatTypeOption(
                    'Public channels',
                    _publicChannels,
                    (v) => setState(() => _publicChannels = v!),
                    textColor,
                    hasSubOption: true,
                    subChecked: _publicChannelsOnlyMy,
                    subEnabled: false, // forced on, disabled
                    onSubChanged: null,
                    parentChecked: _publicChannels,
                  ),

                  // §29.3.3 Media section (SlideWrap)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: _showMediaSection
                        ? _buildMediaSection(headerColor, textColor, accentColor)
                        : const SizedBox.shrink(),
                  ),

                  // §29.3.4 Other Data section
                  _buildSectionHeader('Other', headerColor),
                  _buildOptionWithAbout(
                    'Active sessions',
                    'Exports device and login info.',
                    _sessions,
                    (v) => setState(() => _sessions = v!),
                    textColor,
                    subtextColor,
                  ),
                  _buildOptionWithAbout(
                    'Other data',
                    'Exports web login tokens, contacts block list, etc.',
                    _otherData,
                    (v) => setState(() => _otherData = v!),
                    textColor,
                    subtextColor,
                  ),

                  // §29.3.5 Output Format section
                  _buildSectionHeader('Output format', headerColor),
                  _buildLocationLabel(accentColor, subtextColor),
                  _buildFormatRadio(
                      'Human-readable HTML', _ExportFormat.html, textColor),
                  _buildFormatRadio(
                      'Machine-readable JSON', _ExportFormat.json, textColor),
                  _buildFormatRadio(
                      'HTML and JSON', _ExportFormat.htmlAndJson, textColor),
                  const SizedBox(height: 8),
                ],
              ),
              // Top fade shadow
              if (_showTopShadow)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [shadowColor, shadowColor.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
              // Bottom fade shadow
              if (_showBottomShadow)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [shadowColor, shadowColor.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // §29.3.6 Bottom buttons
        _buildBottomButtons(accentColor, subtextColor),
      ],
    );
  }

  Widget _buildSectionHeader(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 9),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildOptionWithAbout(
    String label,
    String about,
    bool value,
    ValueChanged<bool?> onChanged,
    Color textColor,
    Color subtextColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: value,
                  onChanged: onChanged,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 14, color: textColor),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
          child: Text(
            about,
            style: TextStyle(
              fontSize: 13,
              color: subtextColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChatTypeOption(
    String label,
    bool value,
    ValueChanged<bool?> onChanged,
    Color textColor, {
    required bool hasSubOption,
    bool subChecked = false,
    bool subEnabled = true,
    ValueChanged<bool?>? onSubChanged,
    bool parentChecked = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: value,
                  onChanged: onChanged,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 14, color: textColor),
                ),
              ),
            ],
          ),
        ),
        if (hasSubOption)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: parentChecked
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(56, 4, 22, 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: subChecked,
                            onChanged: subEnabled ? onSubChanged : null,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Only my messages',
                          style: TextStyle(
                            fontSize: 14,
                            color: subEnabled
                                ? textColor
                                : textColor.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
      ],
    );
  }

  Widget _buildMediaSection(Color headerColor, Color textColor, Color accentColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Media', headerColor),
        _buildMediaCheckbox('Photos', _mediaPhotos,
            (v) => setState(() => _mediaPhotos = v!), textColor),
        _buildMediaCheckbox('Video files', _mediaVideo,
            (v) => setState(() => _mediaVideo = v!), textColor),
        _buildMediaCheckbox('Voice messages', _mediaVoice,
            (v) => setState(() => _mediaVoice = v!), textColor),
        _buildMediaCheckbox('Video messages', _mediaVideoMessage,
            (v) => setState(() => _mediaVideoMessage = v!), textColor),
        _buildMediaCheckbox('Stickers', _mediaSticker,
            (v) => setState(() => _mediaSticker = v!), textColor),
        _buildMediaCheckbox('GIFs', _mediaGif,
            (v) => setState(() => _mediaGif = v!), textColor),
        _buildMediaCheckbox('Files', _mediaFile,
            (v) => setState(() => _mediaFile = v!), textColor),
        // Size limit slider
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '$_sizeLimitMB MB',
                style: TextStyle(fontSize: 13, color: accentColor),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5),
              trackHeight: 3,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: _sizeSliderPos,
              min: 0,
              max: 99,
              divisions: 99,
              onChanged: (v) => setState(() => _sizeSliderPos = v),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaCheckbox(
    String label,
    bool value,
    ValueChanged<bool?> onChanged,
    Color textColor,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 14, color: textColor)),
        ],
      ),
    );
  }

  Widget _buildLocationLabel(Color accentColor, Color subtextColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
      child: Row(
        children: [
          Text('Location: ', style: TextStyle(fontSize: 13, color: subtextColor)),
          Expanded(
            child: GestureDetector(
              onTap: () {
                // Would open folder picker in production
              },
              child: Text(
                'Downloads/TelegramExport',
                style: TextStyle(
                  fontSize: 13,
                  color: accentColor,
                  decoration: TextDecoration.underline,
                  decorationColor: accentColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatRadio(String label, _ExportFormat value, Color textColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Radio<_ExportFormat>(
              value: value,
              groupValue: _format,
              onChanged: (v) => setState(() => _format = v!),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 14, color: textColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButtons(Color accentColor, Color subtextColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? const Color(0xFF0E1621) : const Color(0xFFE0E0E0);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: subtextColor,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              textStyle: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w500),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          if (_anyTypeSelected)
            TextButton(
              onPressed: () {
                setState(() => _phase = ExportPhase.processing);
              },
              style: TextButton.styleFrom(
                foregroundColor: accentColor,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                textStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500),
              ),
              child: const Text('Export'),
            ),
        ],
      ),
    );
  }

  Widget _buildProcessingPlaceholder(Color subtextColor) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: subtextColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Please wait, export is in progress.',
            style: TextStyle(fontSize: 14, color: subtextColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedPlaceholder(Color subtextColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 64, color: accentColor),
          const SizedBox(height: 16),
          Text(
            'Your data was successfully exported.',
            style: TextStyle(fontSize: 14, color: subtextColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorPlaceholder(Color subtextColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final errorColor =
        isDark ? const Color(0xFFEC3942) : const Color(0xFFD14E4E);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 64, color: errorColor),
          const SizedBox(height: 16),
          Text(
            'Export failed.',
            style: TextStyle(fontSize: 14, color: errorColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ExportSuggestBox extends StatelessWidget {
  final VoidCallback? onStart;

  const _ExportSuggestBox({this.onStart});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final textColor = isDark ? const Color(0xFFAAAAAA) : const Color(0xFF555555);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 360,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Export Your Data',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'You can export your data from Telegram, including chats, '
                'messages, and media. The export will be processed by '
                'Telegram servers and may take some time.',
                style: TextStyle(fontSize: 14, color: textColor, height: 1.4),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onStart?.call();
                    },
                    child: Text(
                      'OK',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
