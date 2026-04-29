import 'dart:async';

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

class _ExportStepInfo {
  final String label;
  double progress;
  String info;

  _ExportStepInfo({required this.label, this.progress = 0.0, this.info = ''});
}

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

  // Date range filter (per-chat/per-topic mode)
  DateTime? _fromDate;
  DateTime? _tillDate;
  int _fromTimeSeconds = 0;
  int _tillTimeSeconds = 86340; // 23:59

  bool get _isPerChat => widget.target.mode != ExportMode.full;

  static final DateTime _telegramLaunchDate = DateTime(2013, 8, 1);
  static const int _kOffset = 600;

  // Scroll state for fade shadows
  final ScrollController _scrollController = ScrollController();
  bool _showTopShadow = false;
  bool _showBottomShadow = true;

  List<_ExportStepInfo> _exportSteps = [];
  Timer? _exportTimer;
  Timer? _skipFileTimer;
  bool _showSkipFile = false;
  int _currentStepIndex = 0;

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
    _exportTimer?.cancel();
    _skipFileTimer?.cancel();
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
        _exportTimer?.cancel();
        _skipFileTimer?.cancel();
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

  void _startExport() {
    _exportSteps = _buildExportStepList();
    _currentStepIndex = 0;
    _showSkipFile = false;
    setState(() => _phase = ExportPhase.processing);
    _exportTimer =
        Timer.periodic(const Duration(milliseconds: 100), _tickExport);
    _resetSkipFileTimer();
  }

  List<_ExportStepInfo> _buildExportStepList() {
    final steps = <_ExportStepInfo>[];
    if (_isPerChat) {
      steps.add(_ExportStepInfo(label: 'Initializing'));
      steps.add(
          _ExportStepInfo(label: widget.target.chatTitle ?? 'Chat'));
      return steps;
    }
    steps.add(_ExportStepInfo(label: 'Initializing'));
    steps.add(_ExportStepInfo(label: 'Dialogs list'));
    if (_personalInfo) {
      steps.add(_ExportStepInfo(label: 'Personal info'));
      steps.add(_ExportStepInfo(label: 'Userpics'));
    }
    if (_stories) steps.add(_ExportStepInfo(label: 'Stories'));
    if (_profileMusic) steps.add(_ExportStepInfo(label: 'Profile music'));
    if (_contacts) steps.add(_ExportStepInfo(label: 'Contacts'));
    if (_sessions) steps.add(_ExportStepInfo(label: 'Sessions'));
    if (_otherData) steps.add(_ExportStepInfo(label: 'Other data'));
    if (_anyChatSelected) steps.add(_ExportStepInfo(label: 'Chats'));
    return steps;
  }

  void _tickExport(Timer timer) {
    if (_currentStepIndex >= _exportSteps.length) {
      timer.cancel();
      _skipFileTimer?.cancel();
      setState(() => _phase = ExportPhase.completed);
      return;
    }
    final step = _exportSteps[_currentStepIndex];
    final speed = 0.02 + 0.01 * _currentStepIndex;
    step.progress = (step.progress + speed).clamp(0.0, 1.0);
    if (step.progress < 1.0) {
      step.info = '${(step.progress * 100).toInt()}%';
    } else {
      step.info = 'Done';
      _currentStepIndex++;
      _showSkipFile = false;
      _resetSkipFileTimer();
    }
    setState(() {});
  }

  void _resetSkipFileTimer() {
    _skipFileTimer?.cancel();
    _showSkipFile = false;
    _skipFileTimer = Timer(const Duration(seconds: 5), () {
      if (_phase == ExportPhase.processing && mounted) {
        setState(() => _showSkipFile = true);
      }
    });
  }

  void _skipCurrentFile() {
    if (_currentStepIndex < _exportSteps.length) {
      _exportSteps[_currentStepIndex].progress = 1.0;
      _exportSteps[_currentStepIndex].info = 'Skipped';
      _currentStepIndex++;
      _showSkipFile = false;
      _resetSkipFileTimer();
      setState(() {});
    }
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
            height: _isPerChat ? 540.0 : _exportPanelHeight,
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
        return _isPerChat
            ? _buildPerChatSettings(subtextColor)
            : _buildFullExportSettings(subtextColor);
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
          if (_isPerChat || _anyTypeSelected)
            TextButton(
              onPressed: _startExport,
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

  Widget _buildPerChatSettings(Color subtextColor) {
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('$_sizeLimitMB MB',
                            style: TextStyle(fontSize: 13, color: accentColor)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 7.5),
                        trackHeight: 3,
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 14),
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
                  _buildCombinedFormatLocation(accentColor, subtextColor),
                  _buildDateRangeFilter(accentColor, subtextColor),
                  const SizedBox(height: 8),
                ],
              ),
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
        _buildBottomButtons(accentColor, subtextColor),
      ],
    );
  }

  Widget _buildCombinedFormatLocation(Color accentColor, Color subtextColor) {
    final formatName = switch (_format) {
      _ExportFormat.html => 'HTML',
      _ExportFormat.json => 'JSON',
      _ExportFormat.htmlAndJson => 'HTML and JSON',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
      child: Wrap(
        children: [
          Text('Export data in ',
              style: TextStyle(fontSize: 13, color: subtextColor)),
          GestureDetector(
            onTap: () async {
              final chosen = await _showChooseFormatBox();
              if (chosen != null) setState(() => _format = chosen);
            },
            child: Text(
              formatName,
              style: TextStyle(
                fontSize: 13,
                color: accentColor,
                decoration: TextDecoration.underline,
                decorationColor: accentColor,
              ),
            ),
          ),
          Text(' to ', style: TextStyle(fontSize: 13, color: subtextColor)),
          GestureDetector(
            onTap: () {},
            child: Text(
              'Downloads/TelegramExport',
              style: TextStyle(
                fontSize: 13,
                color: accentColor,
                decoration: TextDecoration.underline,
                decorationColor: accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateLabel(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatTimeLabel(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  DateTime _combineDateAndTime(DateTime date, int timeSeconds) {
    return DateTime(date.year, date.month, date.day, timeSeconds ~/ 3600,
        (timeSeconds % 3600) ~/ 60);
  }

  void _enforceOffset() {
    if (_fromDate == null || _tillDate == null) return;
    final from = _combineDateAndTime(_fromDate!, _fromTimeSeconds);
    final till = _combineDateAndTime(_tillDate!, _tillTimeSeconds);
    final diff = till.difference(from).inSeconds;
    if (diff < _kOffset) {
      final adjusted = from.add(const Duration(seconds: _kOffset));
      _tillDate = DateTime(adjusted.year, adjusted.month, adjusted.day);
      _tillTimeSeconds = adjusted.hour * 3600 + adjusted.minute * 60;
    }
  }

  Widget _buildDateRangeFilter(Color accentColor, Color subtextColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
      child: Wrap(
        children: [
          Text('From ', style: TextStyle(fontSize: 13, color: subtextColor)),
          GestureDetector(
            onTap: () async {
              final picked = await _showCalendarBox(
                initialDate: _fromDate,
                minDate: _telegramLaunchDate,
                maxDate: _tillDate ?? DateTime.now(),
                resetLabel: 'From the beginning',
              );
              if (picked != null) {
                setState(() {
                  _fromDate = picked.isReset ? null : picked.date;
                  _enforceOffset();
                });
              }
            },
            child: Text(
              _fromDate != null
                  ? _formatDateLabel(_fromDate!)
                  : 'the beginning',
              style: TextStyle(
                fontSize: 13,
                color: accentColor,
                decoration: TextDecoration.underline,
                decorationColor: accentColor,
              ),
            ),
          ),
          if (_fromDate != null) ...[
            Text(', ', style: TextStyle(fontSize: 13, color: subtextColor)),
            GestureDetector(
              onTap: () async {
                final seconds = await _showChooseTimeBox(_fromTimeSeconds);
                if (seconds != null) {
                  setState(() {
                    _fromTimeSeconds = seconds;
                    _enforceOffset();
                  });
                }
              },
              child: Text(
                _formatTimeLabel(_fromTimeSeconds),
                style: TextStyle(
                  fontSize: 13,
                  color: accentColor,
                  decoration: TextDecoration.underline,
                  decorationColor: accentColor,
                ),
              ),
            ),
          ],
          Text(' till ', style: TextStyle(fontSize: 13, color: subtextColor)),
          GestureDetector(
            onTap: () async {
              final picked = await _showCalendarBox(
                initialDate: _tillDate,
                minDate: _fromDate ?? _telegramLaunchDate,
                maxDate: DateTime.now(),
                resetLabel: 'Till now',
              );
              if (picked != null) {
                setState(() {
                  _tillDate = picked.isReset ? null : picked.date;
                  _enforceOffset();
                });
              }
            },
            child: Text(
              _tillDate != null ? _formatDateLabel(_tillDate!) : 'now',
              style: TextStyle(
                fontSize: 13,
                color: accentColor,
                decoration: TextDecoration.underline,
                decorationColor: accentColor,
              ),
            ),
          ),
          if (_tillDate != null) ...[
            Text(', ', style: TextStyle(fontSize: 13, color: subtextColor)),
            GestureDetector(
              onTap: () async {
                final seconds = await _showChooseTimeBox(_tillTimeSeconds);
                if (seconds != null) {
                  setState(() {
                    _tillTimeSeconds = seconds;
                    _enforceOffset();
                  });
                }
              },
              child: Text(
                _formatTimeLabel(_tillTimeSeconds),
                style: TextStyle(
                  fontSize: 13,
                  color: accentColor,
                  decoration: TextDecoration.underline,
                  decorationColor: accentColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<_CalendarResult?> _showCalendarBox({
    DateTime? initialDate,
    required DateTime minDate,
    required DateTime maxDate,
    String? resetLabel,
  }) {
    return showDialog<_CalendarResult>(
      context: context,
      builder: (ctx) => _CalendarBox(
        initialDate: initialDate,
        minDate: minDate,
        maxDate: maxDate,
        resetLabel: resetLabel,
      ),
    );
  }

  Future<int?> _showChooseTimeBox(int currentSeconds) {
    return showDialog<int>(
      context: context,
      builder: (ctx) => _ChooseTimeBox(initialSeconds: currentSeconds),
    );
  }

  Future<_ExportFormat?> _showChooseFormatBox() {
    return showDialog<_ExportFormat>(
      context: context,
      builder: (ctx) => _ChooseFormatBox(current: _format),
    );
  }

  Widget _buildProcessingPlaceholder(Color subtextColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final activeFg =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final inactiveFg =
        isDark ? const Color(0xFF283848) : const Color(0xFFE0E0E0);
    final attentionFg =
        isDark ? const Color(0xFFEC3942) : const Color(0xFFD14E4E);
    final linkColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

    final visibleSteps = <_ExportStepInfo>[];
    if (_exportSteps.isNotEmpty) {
      final activeIdx =
          _currentStepIndex.clamp(0, _exportSteps.length - 1);
      final startIdx = (activeIdx - 2).clamp(0, _exportSteps.length);
      for (var i = startIdx;
          i <= activeIdx && i < _exportSteps.length;
          i++) {
        visibleSteps.add(_exportSteps[i]);
      }
    }

    return Column(
      children: [
        const SizedBox(height: 10),
        for (final step in visibleSteps)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 5, 22, 5),
            child: SizedBox(
              height: 30,
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            step.label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          step.info,
                          style: TextStyle(
                              fontSize: 14, color: subtextColor),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 3,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          children: [
                            Container(
                              width: constraints.maxWidth,
                              height: 3,
                              color: inactiveFg,
                            ),
                            AnimatedContainer(
                              duration:
                                  const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              width: constraints.maxWidth *
                                  step.progress,
                              height: 3,
                              color: activeFg,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        AnimatedOpacity(
          opacity: _showSkipFile ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: _showSkipFile ? _skipCurrentFile : null,
                child: MouseRegion(
                  cursor: _showSkipFile
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
                  child: Text(
                    'Skip file',
                    style: TextStyle(
                      fontSize: 13,
                      color: linkColor,
                      decoration: TextDecoration.underline,
                      decorationColor: linkColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Please wait, export is in progress.',
              style: TextStyle(fontSize: 14, color: subtextColor),
            ),
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(bottom: 30),
          child: SizedBox(
            width: 200,
            height: 44,
            child: ElevatedButton(
              onPressed: _handleClose,
              style: ElevatedButton.styleFrom(
                backgroundColor: attentionFg,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              child: const Text('Stop'),
            ),
          ),
        ),
      ],
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

class _CalendarResult {
  final DateTime? date;
  final bool isReset;
  const _CalendarResult({this.date, this.isReset = false});
}

class _CalendarBox extends StatefulWidget {
  final DateTime? initialDate;
  final DateTime minDate;
  final DateTime maxDate;
  final String? resetLabel;

  const _CalendarBox({
    this.initialDate,
    required this.minDate,
    required this.maxDate,
    this.resetLabel,
  });

  @override
  State<_CalendarBox> createState() => _CalendarBoxState();
}

class _CalendarBoxState extends State<_CalendarBox> {
  late int _year;
  late int _month;
  DateTime? _selected;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  static const _weekDays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
    final now = widget.initialDate ?? DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  void _prevMonth() {
    setState(() {
      _month--;
      if (_month < 1) {
        _month = 12;
        _year--;
      }
    });
  }

  void _nextMonth() {
    setState(() {
      _month++;
      if (_month > 12) {
        _month = 1;
        _year++;
      }
    });
  }

  bool _canGoPrev() {
    return _year > widget.minDate.year ||
        (_year == widget.minDate.year && _month > widget.minDate.month);
  }

  bool _canGoNext() {
    return _year < widget.maxDate.year ||
        (_year == widget.maxDate.year && _month < widget.maxDate.month);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final startWeekday = DateTime(_year, _month, 1).weekday;
    final offset = startWeekday - 1;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 320,
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
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.chevron_left,
                          color:
                              _canGoPrev() ? textColor : subtextColor),
                      onPressed: _canGoPrev() ? _prevMonth : null,
                      splashRadius: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 32, minHeight: 32),
                    ),
                    Expanded(
                      child: Text(
                        '${_monthNames[_month - 1]} $_year',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.chevron_right,
                          color:
                              _canGoNext() ? textColor : subtextColor),
                      onPressed: _canGoNext() ? _nextMonth : null,
                      splashRadius: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: _weekDays
                      .map((d) => SizedBox(
                            width: (320 - 28) / 7,
                            height: 30,
                            child: Center(
                              child: Text(d,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: subtextColor,
                                      fontWeight: FontWeight.w500)),
                            ),
                          ))
                      .toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: _buildDayGrid(offset, daysInMonth, textColor,
                    subtextColor, accentColor),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                child: Row(
                  children: [
                    if (widget.resetLabel != null)
                      TextButton(
                        onPressed: () => Navigator.of(context)
                            .pop(const _CalendarResult(isReset: true)),
                        style: TextButton.styleFrom(
                          foregroundColor: accentColor,
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                        child: Text(widget.resetLabel!),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: subtextColor,
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayGrid(int offset, int daysInMonth, Color textColor,
      Color subtextColor, Color accentColor) {
    final cellWidth = (320.0 - 28) / 7;
    const cellHeight = 38.0;
    const selectedSize = 32.0;

    final rows = <Widget>[];
    var day = 1;

    for (var row = 0; row < 6 && day <= daysInMonth; row++) {
      final cells = <Widget>[];
      for (var col = 0; col < 7; col++) {
        final cellIndex = row * 7 + col;
        if (cellIndex < offset || day > daysInMonth) {
          cells.add(SizedBox(width: cellWidth, height: cellHeight));
        } else {
          final thisDay = day;
          final date = DateTime(_year, _month, thisDay);
          final isDisabled = date.isBefore(DateTime(widget.minDate.year,
                  widget.minDate.month, widget.minDate.day)) ||
              date.isAfter(widget.maxDate);
          final isSelected = _selected != null &&
              _selected!.year == _year &&
              _selected!.month == _month &&
              _selected!.day == thisDay;
          final now = DateTime.now();
          final isToday = now.year == _year &&
              now.month == _month &&
              now.day == thisDay;

          cells.add(
            GestureDetector(
              onTap: isDisabled
                  ? null
                  : () {
                      Navigator.of(context)
                          .pop(_CalendarResult(date: date));
                    },
              child: SizedBox(
                width: cellWidth,
                height: cellHeight,
                child: Center(
                  child: Container(
                    width: selectedSize,
                    height: selectedSize,
                    decoration: isSelected
                        ? BoxDecoration(
                            shape: BoxShape.circle, color: accentColor)
                        : isToday
                            ? BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: accentColor, width: 1),
                              )
                            : null,
                    alignment: Alignment.center,
                    child: Text(
                      '$thisDay',
                      style: TextStyle(
                        fontSize: 13,
                        color: isSelected
                            ? Colors.white
                            : isDisabled
                                ? subtextColor.withValues(alpha: 0.4)
                                : textColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          day++;
        }
      }
      rows.add(Row(children: cells));
    }

    return Column(children: rows);
  }
}

class _ChooseTimeBox extends StatefulWidget {
  final int initialSeconds;
  const _ChooseTimeBox({required this.initialSeconds});

  @override
  State<_ChooseTimeBox> createState() => _ChooseTimeBoxState();
}

class _ChooseTimeBoxState extends State<_ChooseTimeBox> {
  late TextEditingController _hoursController;
  late TextEditingController _minutesController;
  late FocusNode _hoursFocus;
  late FocusNode _minutesFocus;

  @override
  void initState() {
    super.initState();
    final h = widget.initialSeconds ~/ 3600;
    final m = (widget.initialSeconds % 3600) ~/ 60;
    _hoursController =
        TextEditingController(text: h.toString().padLeft(2, '0'));
    _minutesController =
        TextEditingController(text: m.toString().padLeft(2, '0'));
    _hoursFocus = FocusNode();
    _minutesFocus = FocusNode();
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    _hoursFocus.dispose();
    _minutesFocus.dispose();
    super.dispose();
  }

  int get _currentSeconds {
    final h = int.tryParse(_hoursController.text) ?? 0;
    final m = int.tryParse(_minutesController.text) ?? 0;
    return (h.clamp(0, 23) * 3600) + (m.clamp(0, 59) * 60);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 320,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
                child: Text(
                  'Choose Time',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                child: SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _hoursController,
                          focusNode: _hoursFocus,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 2,
                          decoration: InputDecoration(
                            hintText: 'hours',
                            hintStyle: TextStyle(color: subtextColor),
                            counterText: '',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 10),
                          ),
                          style:
                              TextStyle(fontSize: 15, color: textColor),
                          onChanged: (v) {
                            if (v.length == 2) {
                              _minutesFocus.requestFocus();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _minutesController,
                          focusNode: _minutesFocus,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 2,
                          decoration: InputDecoration(
                            hintText: 'minutes',
                            hintStyle: TextStyle(color: subtextColor),
                            counterText: '',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 10),
                          ),
                          style:
                              TextStyle(fontSize: 15, color: textColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 14, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: subtextColor,
                        textStyle: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_currentSeconds),
                      style: TextButton.styleFrom(
                        foregroundColor: accentColor,
                        textStyle: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      child: const Text('Save'),
                    ),
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

class _ChooseFormatBox extends StatefulWidget {
  final _ExportFormat current;
  const _ChooseFormatBox({required this.current});

  @override
  State<_ChooseFormatBox> createState() => _ChooseFormatBoxState();
}

class _ChooseFormatBoxState extends State<_ChooseFormatBox> {
  late _ExportFormat _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 320,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 4),
                child: Text(
                  'Export Format',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              _buildRadio(
                  'Human-readable HTML', _ExportFormat.html, textColor),
              _buildRadio(
                  'Machine-readable JSON', _ExportFormat.json, textColor),
              _buildRadio(
                  'HTML and JSON', _ExportFormat.htmlAndJson, textColor),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 14, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: subtextColor,
                        textStyle: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_selected),
                      style: TextButton.styleFrom(
                        foregroundColor: accentColor,
                        textStyle: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRadio(
      String label, _ExportFormat value, Color textColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Radio<_ExportFormat>(
              value: value,
              groupValue: _selected,
              onChanged: (v) => setState(() => _selected = v!),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 14, color: textColor)),
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
