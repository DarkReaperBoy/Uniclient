import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../theme/telegram_palette.dart';
import '../utils/native_files.dart';
import 'package:uniclient/utils/debug.dart';

const double _exportPanelWidth = 364;
const double _exportPanelHeight = 480;
const double _boxRadius = 8;
const double _titleBarHeight = 48;
const double _exportTopBarHeight = 36.0;

class ExportTopBar extends StatefulWidget {
  const ExportTopBar({super.key});

  static const height = _exportTopBarHeight;

  @override
  State<ExportTopBar> createState() => _ExportTopBarState();
}

class _ExportTopBarState extends State<ExportTopBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideAnim;

  @override
  void initState() {
    super.initState();
    _slideAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..forward();
  }

  @override
  void dispose() {
    _slideAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = context.watch<ChatState>();
    final palette = PaletteProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shadowColor = palette.shadowFg;

    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: _slideAnim,
        curve: Curves.easeOutCubic,
      ),
      axisAlignment: -1.0,
      child: GestureDetector(
        onTap: chatState.exportOnTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: _exportTopBarHeight - 3,
              color: palette.mediaPlayerBg,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Text(
                    // AyuGram top bar: lng_export_progress_title (bold) + ' ' +
                    // QChar(0x2013) en-dash (export_view_top_bar.cpp:89-91).
                    'Exporting your data \u2013 ',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: palette.windowBoldFg,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      chatState.exportStepLabel,
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.windowBoldFg,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (chatState.exportInfoText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        chatState.exportInfoText,
                        style: TextStyle(
                          fontSize: 13,
                          color: palette.windowSubTextFg,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(color: palette.mediaPlayerInactiveFg),
                  ),
                  FractionallySizedBox(
                    widthFactor: chatState.exportProgress.clamp(0.0, 1.0),
                    alignment: Alignment.centerLeft,
                    child: Container(
                      color: palette.mediaPlayerActiveFg,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum ExportMode { full, perChat, perTopic }

enum ExportPhase { settings, processing, completed, error }

enum _ExportErrorType { takeoutInvalid, takeoutInitDelay, diskIo, genericApi }

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
      // Full-export panel title — AyuGram lng_export_title. The English
      // ground-truth value in lang.strings:6823 is "Export Your Data"
      // (export_view_panel_controller.cpp:178-179).
      case ExportMode.full:
        return 'Export Your Data';
      // Single-peer / topic panel title — AyuGram lng_export_header_chats /
      // lng_export_header_topic (lang.strings:6838-6839), the very same strings
      // used for the full-export "Chats" section header (chat_export.dart:1428).
      // The panel title and that section header must be identical text.
      // (export_view_panel_controller.cpp:175-179)
      case ExportMode.perChat:
        return 'Chat export settings';
      case ExportMode.perTopic:
        return 'Topic export settings';
    }
  }

  String get panelTitle => settingsTitle;
}

void showExportPanel(BuildContext context, ExportTarget target) {
  _ExportPanelController.show(context, target);
}

void showExportPanelWithOverlay(OverlayState overlay, ExportTarget target) {
  _ExportPanelController.showWithOverlay(overlay, target);
}

class _ExportPanelController {
  static OverlayEntry? _entry;
  static ValueNotifier<bool> _visible = ValueNotifier(true);
  static String? _activeAccountId;

  static void show(BuildContext context, ExportTarget target) {
    final overlay = Overlay.maybeOf(context) ?? Navigator.maybeOf(context)?.overlay;
    if (overlay == null) return;
    _showInOverlay(overlay, target);
  }

  static void showWithOverlay(OverlayState overlay, ExportTarget target) {
    _showInOverlay(overlay, target);
  }

  static void _showInOverlay(OverlayState overlay, ExportTarget target) {
    if (_entry != null && _activeAccountId != null &&
        _activeAccountId != target.accountId) {
      return;
    }
    close();
    _visible = ValueNotifier(true);
    _activeAccountId = target.accountId;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FloatingExportPanel(
        target: target,
        onClose: close,
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  static void showAndActivate(BuildContext context, ExportTarget target) {
    if (_entry != null && _activeAccountId == target.accountId) {
      _visible.value = true;
      final overlay = Overlay.maybeOf(context) ?? Navigator.maybeOf(context)?.overlay;
      if (overlay != null) {
        _entry!.remove();
        overlay.insert(_entry!);
      }
      return;
    }
    show(context, target);
  }

  static void setHidden(bool hidden) {
    _visible.value = !hidden;
  }

  static void close() {
    if (_entry == null) return;
    _visible.value = false;
    try { _entry!.remove(); } catch (e) {
      Debug.log('chat_export', '_entry!.remove(): $e');
    }
    _entry = null;
    _activeAccountId = null;
  }
}

class _FloatingExportPanel extends StatefulWidget {
  final ExportTarget target;
  final VoidCallback onClose;

  const _FloatingExportPanel({required this.target, required this.onClose});

  @override
  State<_FloatingExportPanel> createState() => _FloatingExportPanelState();
}

class _FloatingExportPanelState extends State<_FloatingExportPanel>
    with SingleTickerProviderStateMixin {
  Offset? _position;
  late AnimationController _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..forward();
  }

  @override
  void dispose() {
    _fadeAnim.dispose();
    super.dispose();
  }

  void _handleClose() {
    _fadeAnim.reverse().then((_) {
      widget.onClose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Fixed panel height for every mode — AyuGram uses a single
    // st::exportPanelSize (364×480) for single-peer, topic and full export
    // (export.style:13, setInnerSize at export_view_panel_controller.cpp:180).
    const panelH = _exportPanelHeight;
    _position ??= Offset(
      (size.width - _exportPanelWidth) / 2,
      (size.height - panelH) / 2,
    );
    return ValueListenableBuilder<bool>(
      valueListenable: _ExportPanelController._visible,
      builder: (context, visible, child) {
        return Offstage(
          offstage: !visible,
          child: child,
        );
      },
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(
          children: [
            Positioned(
              left: _position!.dx,
              top: _position!.dy,
              child: _ExportPanelDialog(
                target: widget.target,
                onClose: _handleClose,
                onTitleDrag: (delta) {
                  setState(() => _position = _position! + delta);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showExportSuggestBox(BuildContext context, {String? accountId}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ExportSuggestBox(accountId: accountId),
  );
}

class _ExportPanelDialog extends StatefulWidget {
  final ExportTarget target;
  final VoidCallback? onClose;
  final void Function(Offset)? onTitleDrag;

  const _ExportPanelDialog({
    required this.target,
    this.onClose,
    this.onTitleDrag,
  });

  @override
  State<_ExportPanelDialog> createState() => _ExportPanelDialogState();
}

enum _ExportFormat { html, json, htmlAndJson }

class _ExportStepInfo {
  String label;
  double progress;
  String info;
  double opacity;
  bool hidden;
  bool wasReported;

  _ExportStepInfo({required this.label, this.progress = 0.0, this.info = '', this.opacity = 1.0, this.hidden = false, this.wasReported = false});
}

/// One row of the export progress view — a faithful analogue of AyuGram's
/// Export::View::Content::Row (export_view_content.h). [empty] rows render as
/// blank fixed-height padding so the fixed multi-row layout height stays
/// constant (AyuGram pads to requiredRows with empty Content::Row{}).
class _ProgressRow {
  final String label;
  final String info;
  final double progress;
  final bool empty;
  const _ProgressRow({
    this.label = '',
    this.info = '',
    this.progress = 0.0,
    this.empty = false,
  });
}

class _ExportPanelDialogState extends State<_ExportPanelDialog>
    with WidgetsBindingObserver {
  ExportPhase _phase = ExportPhase.settings;
  /// Cached ChatState ref (set in didChangeDependencies) so dispose() can stop
  /// the export bar without a context provider lookup — looking up an inherited
  /// widget via context in dispose() throws "deactivated widget's ancestor is
  /// unsafe".
  ChatState? _chatStateRef;

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

  // "Only my messages" sub-options. AyuGram's DefaultFullChats() is only
  // PersonalChats | BotChats, and each checkbox's initial state is
  // `(fullChats & types) != types` — so for private groups/channels (not in
  // fullChats) "Only my messages" is CHECKED by default. Defaulting these to
  // false would export every member's messages on a fresh export.
  // (export_settings.h:115-118, export_view_settings.cpp:751)
  bool _privateGroupsOnlyMy = true;
  bool _privateChannelsOnlyMy = true;
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

  // Export output path
  String _exportLocation = '';

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
  bool _exportDone = false;
  Timer? _skipFileTimer;
  Timer? _saveSettingsTimer;
  Timer? _fadeOutTimer;
  bool _showSkipFile = false;
  int _currentStepIndex = 0;
  int _totalFiles = 0;
  int _totalSizeBytes = 0;
  int _fileRandomId = 0;
  String _exportPath = '';

  // Live state for the fixed multi-row progress view (item #5). AyuGram's
  // ProgressWidget shows a fixed set of rows (2 single-peer / 3 full) that update
  // in place: a "main" step row, the current-entity row, and a per-file byte row.
  // _entity* carries the current sub-entity (chat title / "N messages"); _bytes*
  // carries per-file download bytes for FormatDownloadText.
  String _entityInfo = '';
  double _entityProgress = 0.0;
  String _bytesName = '';
  int _bytesLoaded = 0;
  int _bytesCount = 0;

  StreamSubscription<ExportProgressEvent>? _progressSub;
  StreamSubscription<ExportErrorEvent>? _errorSub;
  StreamSubscription<ExportCompleteEvent>? _completeSub;

  _ExportErrorType _errorType = _ExportErrorType.genericApi;
  String _errorDetail = '';

  String get _title {
    switch (_phase) {
      case ExportPhase.processing:
        // AyuGram: progress state title is lng_export_progress_title; once the
        // export reaches FinishedState the panel title is reset to
        // lng_export_title ("Export Your Data") regardless of single-peer/topic
        // mode (export_view_panel_controller.cpp:306,408-410).
        return _exportDone ? 'Export Your Data' : 'Exporting your data';
      case ExportPhase.completed:
        return 'Export Your Data';
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

  String get _defaultExportLocation {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    return home.isEmpty ? 'Downloads/TelegramExport' : '$home/Downloads/TelegramExport';
  }

  String get _displayExportLocation {
    if (_exportLocation.isNotEmpty) return _exportLocation;
    return 'Downloads/TelegramExport';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_updateShadows);
    _loadExportSettings();
    _loadEngineSettings();
  }

  void _loadEngineSettings() {
    final accountId = widget.target.accountId;
    if (accountId == null || accountId.isEmpty) return;
    final engine = context.read<EngineService>();
    engine.loadExportSettings(accountId).then((data) {
      if (!mounted || data.isEmpty) return;
      bool changed = false;
      void merge<T>(String key, T current, void Function(T) setter) {
        final val = data[key];
        if (val is T && val != current) {
          setter(val);
          changed = true;
        }
      }
      merge<bool>('personalInfo', _personalInfo, (v) => _personalInfo = v);
      merge<bool>('contacts', _contacts, (v) => _contacts = v);
      merge<bool>('stories', _stories, (v) => _stories = v);
      merge<bool>('profileMusic', _profileMusic, (v) => _profileMusic = v);
      merge<bool>('personalChats', _personalChats, (v) => _personalChats = v);
      merge<bool>('botChats', _botChats, (v) => _botChats = v);
      merge<bool>('privateGroups', _privateGroups, (v) => _privateGroups = v);
      merge<bool>('privateChannels', _privateChannels, (v) => _privateChannels = v);
      merge<bool>('publicGroups', _publicGroups, (v) => _publicGroups = v);
      merge<bool>('publicChannels', _publicChannels, (v) => _publicChannels = v);
      final newLoc = data['exportLocation'] as String?;
      if (newLoc != null && newLoc != _exportLocation) {
        _exportLocation = newLoc;
        changed = true;
      }
      final fmt = data['format'] as String?;
      if (fmt != null) {
        final newFormat = _ExportFormat.values.firstWhere(
          (e) => e.name == fmt,
          orElse: () => _format,
        );
        if (newFormat != _format) {
          _format = newFormat;
          changed = true;
        }
      }
      if (changed) setState(() {});
    }).catchError((_) {});
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

  String get _exportSettingsPath {
    final dir = context.read<AppState>().configDir;
    return dir.isEmpty ? '' : '$dir/export_settings.json';
  }

  void _loadExportSettings() {
    final path = _exportSettingsPath;
    if (path.isEmpty) return;
    try {
      final file = File(path);
      if (!file.existsSync()) return;
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      _personalInfo = (data['personalInfo'] as bool?) ?? _personalInfo;
      _contacts = (data['contacts'] as bool?) ?? _contacts;
      _stories = (data['stories'] as bool?) ?? _stories;
      _profileMusic = (data['profileMusic'] as bool?) ?? _profileMusic;
      _personalChats = (data['personalChats'] as bool?) ?? _personalChats;
      _botChats = (data['botChats'] as bool?) ?? _botChats;
      _privateGroups = (data['privateGroups'] as bool?) ?? _privateGroups;
      _privateChannels = (data['privateChannels'] as bool?) ?? _privateChannels;
      _publicGroups = (data['publicGroups'] as bool?) ?? _publicGroups;
      _publicChannels = (data['publicChannels'] as bool?) ?? _publicChannels;
      _privateGroupsOnlyMy = (data['privateGroupsOnlyMy'] as bool?) ?? _privateGroupsOnlyMy;
      _privateChannelsOnlyMy = (data['privateChannelsOnlyMy'] as bool?) ?? _privateChannelsOnlyMy;
      _publicGroupsOnlyMy = (data['publicGroupsOnlyMy'] as bool?) ?? _publicGroupsOnlyMy;
      _publicChannelsOnlyMy = (data['publicChannelsOnlyMy'] as bool?) ?? _publicChannelsOnlyMy;
      _mediaPhotos = (data['mediaPhotos'] as bool?) ?? _mediaPhotos;
      _mediaVideo = (data['mediaVideo'] as bool?) ?? _mediaVideo;
      _mediaVoice = (data['mediaVoice'] as bool?) ?? _mediaVoice;
      _mediaVideoMessage = (data['mediaVideoMessage'] as bool?) ?? _mediaVideoMessage;
      _mediaSticker = (data['mediaSticker'] as bool?) ?? _mediaSticker;
      _mediaGif = (data['mediaGif'] as bool?) ?? _mediaGif;
      _mediaFile = (data['mediaFile'] as bool?) ?? _mediaFile;
      _sizeSliderPos = (data['sizeSliderPos'] as num?)?.toDouble() ?? _sizeSliderPos;
      _sessions = (data['sessions'] as bool?) ?? _sessions;
      _otherData = (data['otherData'] as bool?) ?? _otherData;
      _exportLocation = (data['exportLocation'] as String?) ?? '';
      final fmt = data['format'] as String?;
      if (fmt != null) {
        _format = _ExportFormat.values.firstWhere(
          (e) => e.name == fmt,
          orElse: () => _format,
        );
      }
    } catch (e) {
      Debug.log('chat_export', 'final file = File(path): $e');
    }
  }

  Map<String, dynamic> get _settingsMap => {
    'personalInfo': _personalInfo,
    'contacts': _contacts,
    'stories': _stories,
    'profileMusic': _profileMusic,
    'personalChats': _personalChats,
    'botChats': _botChats,
    'privateGroups': _privateGroups,
    'privateChannels': _privateChannels,
    'publicGroups': _publicGroups,
    'publicChannels': _publicChannels,
    'privateGroupsOnlyMy': _privateGroupsOnlyMy,
    'privateChannelsOnlyMy': _privateChannelsOnlyMy,
    'publicGroupsOnlyMy': _publicGroupsOnlyMy,
    'publicChannelsOnlyMy': _publicChannelsOnlyMy,
    'mediaPhotos': _mediaPhotos,
    'mediaVideo': _mediaVideo,
    'mediaVoice': _mediaVoice,
    'mediaVideoMessage': _mediaVideoMessage,
    'mediaSticker': _mediaSticker,
    'mediaGif': _mediaGif,
    'mediaFile': _mediaFile,
    'sizeSliderPos': _sizeSliderPos,
    'sessions': _sessions,
    'otherData': _otherData,
    'format': _format.name,
    'exportLocation': _exportLocation,
  };

  void _saveExportSettings() {
    final accountId = widget.target.accountId;
    if (accountId != null && accountId.isNotEmpty) {
      final engine = context.read<EngineService>();
      engine.saveExportSettings(accountId, _settingsMap).catchError((_) {});
    }
    final path = _exportSettingsPath;
    if (path.isEmpty) return;
    try {
      File(path).writeAsStringSync(jsonEncode(_settingsMap));
    } catch (e) {
      Debug.log('chat_export', 'File(path).writeAsStringSync(jsonEncode(_settingsMap)): $e');
    }
  }

  void _scheduleSave() {
    _saveSettingsTimer?.cancel();
    _saveSettingsTimer = Timer(
      const Duration(milliseconds: 1000),
      _saveExportSettings,
    );
  }

  void _updateSetting(VoidCallback fn) {
    setState(fn);
    _scheduleSave();
  }

  Future<void> _pickExportFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      _updateSetting(() => _exportLocation = result);
    }
  }

  void _openExportFolder() {
    final path = _exportPath.isNotEmpty
        ? _exportPath
        : (_exportLocation.isNotEmpty ? _exportLocation : _defaultExportLocation);
    openFolder(path);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatStateRef = context.read<ChatState>();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _errorSub?.cancel();
    _completeSub?.cancel();
    _skipFileTimer?.cancel();
    _fadeOutTimer?.cancel();
    if (_saveSettingsTimer?.isActive ?? false) {
      _saveSettingsTimer!.cancel();
      _saveExportSettings();
    }
    _scrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _chatStateRef?.stopExportBar();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive && _hideOnDeactivate) {
      _ExportPanelController.setHidden(true);
    } else if (state == AppLifecycleState.resumed) {
      _ExportPanelController.setHidden(false);
    }
  }

  void _closePanel() {
    if (widget.onClose != null) {
      widget.onClose!();
    }
  }

  Future<void> _handleClose() async {
    if (_phase == ExportPhase.processing && !_exportDone) {
      final confirmed = await _showStopConfirmation();
      if (confirmed && mounted) {
        final accountId = widget.target.accountId;
        if (accountId != null && accountId.isNotEmpty) {
          context.read<EngineService>().cancelExport(accountId);
        }
        _progressSub?.cancel();
        _errorSub?.cancel();
        _completeSub?.cancel();
        _skipFileTimer?.cancel();
        context.read<ChatState>().stopExportBar();
        _closePanel();
      }
    } else {
      _closePanel();
    }
  }

  Future<bool> _showStopConfirmation() async {
    final p = PaletteProvider.of(context);
    final boxBg = p.boxBg;
    final boxTextFg = p.boxTextFg;
    final attentionFg = p.attentionButtonFg;
    final cancelFg = p.windowActiveTextFg;

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
                  'Are you sure you want to stop exporting your data?\n\nIf you do, you\'ll need to start over.',
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
    final accountId = widget.target.accountId;
    if (accountId == null || accountId.isEmpty) return;

    _exportSteps = _buildExportStepList();
    _currentStepIndex = 0;
    _showSkipFile = false;
    _totalFiles = 0;
    _totalSizeBytes = 0;
    _exportPath = '';
    _entityInfo = '';
    _entityProgress = 0.0;
    _bytesName = '';
    _bytesLoaded = 0;
    _bytesCount = 0;
    _fadeOutTimer?.cancel();
    setState(() => _phase = ExportPhase.processing);
    context.read<ChatState>().startExportBar(onTap: _bringPanelToFront);
    _resetSkipFileTimer();

    final engine = context.read<EngineService>();

    _progressSub?.cancel();
    _progressSub = engine.onExportProgress
        .where((e) => e.accountId == accountId)
        .listen(_onExportProgress);

    _errorSub?.cancel();
    _errorSub = engine.onExportError
        .where((e) => e.accountId == accountId)
        .listen(_onExportError);

    _completeSub?.cancel();
    _completeSub = engine.onExportComplete
        .where((e) => e.accountId == accountId)
        .listen(_onExportComplete);

    final isDefaultLocation = _exportLocation.isEmpty;
    final exportLocation = isDefaultLocation
        ? _defaultExportLocation
        : _exportLocation;

    final exportParams = <String, dynamic>{
      'personal_info': _personalInfo,
      'contacts': _contacts,
      'stories': _stories,
      'profile_music': _profileMusic,
      'personal_chats': _personalChats,
      'bot_chats': _botChats,
      'private_groups': _privateGroups,
      'private_channels': _privateChannels,
      'public_groups': _publicGroups,
      'public_channels': _publicChannels,
      'full_personal_chats': true,
      'full_bot_chats': true,
      'full_private_groups': !_privateGroupsOnlyMy,
      'full_private_channels': !_privateChannelsOnlyMy,
      'full_public_groups': !_publicGroupsOnlyMy,
      'full_public_channels': !_publicChannelsOnlyMy,
      'media_photos': _mediaPhotos,
      'media_video': _mediaVideo,
      'media_voice': _mediaVoice,
      'media_video_message': _mediaVideoMessage,
      'media_sticker': _mediaSticker,
      'media_gif': _mediaGif,
      'media_file': _mediaFile,
      'size_limit_mb': _sizeLimitMB,
      'format': _format.name,
      'export_location': exportLocation,
      'force_sub_path': isDefaultLocation,
      'chat_id': widget.target.chatId ?? '',
      'topic_root_id': widget.target.topicRootId ?? 0,
      'sessions': _sessions,
      'other_data': _otherData,
    };
    if (_isPerChat && _fromDate != null) {
      final fromEpoch = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day)
          .add(Duration(seconds: _fromTimeSeconds))
          .millisecondsSinceEpoch ~/ 1000;
      exportParams['from_date'] = fromEpoch;
    }
    if (_isPerChat && _tillDate != null) {
      final tillEpoch = DateTime(_tillDate!.year, _tillDate!.month, _tillDate!.day)
          .add(Duration(seconds: _tillTimeSeconds))
          .millisecondsSinceEpoch ~/ 1000;
      exportParams['till_date'] = tillEpoch;
    }
    engine.startExport(accountId, exportParams).catchError((e) {
      if (mounted) {
        _triggerGenericApiError(0, 'StartExport', e.toString());
      }
    });
  }

  void _onExportProgress(ExportProgressEvent event) {
    if (!mounted) return;
    final stepLabel = event.step;
    final stepIdx = event.stepIndex;
    final totalSteps = event.totalSteps;
    final progress = event.progress;
    bool fileIdChanged = false;

    setState(() {
      // A new top-level step starting (progress 0) clears the per-step entity
      // and byte rows so they don't carry stale text into the next step.
      if (stepIdx >= 0 && totalSteps > 0 && progress == 0.0) {
        _entityInfo = '';
        _entityProgress = 0.0;
        _bytesName = '';
        _bytesLoaded = 0;
        _bytesCount = 0;
      }
      if (stepIdx >= 0 && totalSteps > 0) {
        while (_exportSteps.length < totalSteps) {
          _exportSteps.add(_ExportStepInfo(label: 'Step ${_exportSteps.length + 1}'));
        }
        if (stepIdx < _exportSteps.length) {
          final isFirstReport = !_exportSteps[stepIdx].wasReported;
          _exportSteps[stepIdx].label = stepLabel;
          if (progress >= 0) {
            _exportSteps[stepIdx].progress = progress.clamp(0.0, 1.0);
          }
          _exportSteps[stepIdx].info = event.info;
          _exportSteps[stepIdx].wasReported = true;
          if (isFirstReport) {
            _exportSteps[stepIdx].opacity = 0.0;
            final idx = stepIdx;
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (mounted && idx < _exportSteps.length) {
                setState(() => _exportSteps[idx].opacity = 1.0);
              }
            });
          } else {
            _exportSteps[stepIdx].opacity = 1.0;
          }
          if (stepIdx > _currentStepIndex) {
            for (int i = _currentStepIndex; i < stepIdx; i++) {
              _exportSteps[i].progress = 1.0;
              _exportSteps[i].opacity = 0.0;
            }
            _scheduleFadeOutRemoval();
          }
          _currentStepIndex = stepIdx;
        }
      } else {
        final existing = _exportSteps.indexWhere((s) => s.label == stepLabel);
        if (existing >= 0) {
          final isFirstReport = !_exportSteps[existing].wasReported;
          if (progress >= 0) {
            _exportSteps[existing].progress = progress.clamp(0.0, 1.0);
          }
          _exportSteps[existing].info = event.info;
          _exportSteps[existing].wasReported = true;
          if (isFirstReport) {
            _exportSteps[existing].opacity = 0.0;
            final idx = existing;
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (mounted && idx < _exportSteps.length) {
                setState(() => _exportSteps[idx].opacity = 1.0);
              }
            });
          } else {
            _exportSteps[existing].opacity = 1.0;
          }
          if (existing > _currentStepIndex) {
            for (int i = _currentStepIndex; i < existing; i++) {
              _exportSteps[i].progress = 1.0;
              _exportSteps[i].opacity = 0.0;
            }
            _scheduleFadeOutRemoval();
          }
          _currentStepIndex = existing;
        }
      }

      // Current-entity row: sub-step events (stepIndex < 0) carry the entity
      // detail (chat title / "N messages") and its per-entity progress.
      if (stepIdx < 0 && stepLabel.isNotEmpty) {
        _entityInfo = event.info;
        if (progress >= 0) _entityProgress = progress.clamp(0.0, 1.0);
      }
      // Per-file byte row: a byte payload fills it; a top-level step boundary
      // with no byte payload clears it (matches AyuGram pushBytes early-return).
      if (event.bytesCount > 0 || event.bytesName.isNotEmpty) {
        _bytesName = event.bytesName;
        _bytesLoaded = event.bytesLoaded;
        _bytesCount = event.bytesCount;
      } else if (stepIdx >= 0) {
        _bytesName = '';
        _bytesLoaded = 0;
        _bytesCount = 0;
      }

      _totalFiles = event.totalFiles;
      _totalSizeBytes = event.totalSizeBytes;
      if (event.fileRandomId != _fileRandomId) {
        _fileRandomId = event.fileRandomId;
        _showSkipFile = false;
        fileIdChanged = true;
      }
    });

    if (fileIdChanged) _resetSkipFileTimer();
    _syncExportBar();
  }

  void _scheduleFadeOutRemoval() {
    _fadeOutTimer?.cancel();
    _fadeOutTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        for (final s in _exportSteps) {
          if (s.opacity == 0.0) s.hidden = true;
        }
      });
    });
  }

  void _onExportError(ExportErrorEvent event) {
    if (!mounted) return;
    switch (event.errorType) {
      case 'takeout_invalid':
        _triggerTakeoutInvalidError();
      case 'takeout_delay':
        _triggerTakeoutInitDelayError(
          event.hoursRemaining,
          DateTime.fromMillisecondsSinceEpoch(event.availableAtMs),
        );
      case 'disk_io':
        _triggerDiskError(event.path);
      default:
        _triggerGenericApiError(event.code, event.errorName, event.description);
    }
  }

  void _onExportComplete(ExportCompleteEvent event) {
    if (!mounted) return;
    _progressSub?.cancel();
    _errorSub?.cancel();
    _completeSub?.cancel();
    _skipFileTimer?.cancel();
    _exportPath = event.exportPath;
    _totalFiles = event.totalFiles;
    _totalSizeBytes = event.totalSizeBytes;
    setState(() {
      _exportDone = true;
      _showSkipFile = false;
      for (final s in _exportSteps) {
        s.progress = 1.0;
        s.opacity = 1.0;
        s.hidden = false;
        if (!s.wasReported) {
          s.info = 'Skipped';
        } else if (s.info.isEmpty) {
          s.info = 'Done';
        }
        s.wasReported = true;
      }
    });
    context.read<ChatState>().stopExportBar();
  }

  void _bringPanelToFront() {
    _ExportPanelController.showAndActivate(context, widget.target);
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

  // Progress is now driven by engine events via _onExportProgress

  void _syncExportBar() {
    if (_currentStepIndex >= _exportSteps.length) return;
    final step = _exportSteps[_currentStepIndex];
    final totalSteps = _exportSteps.length;
    final overallProgress = totalSteps > 0
        ? (_currentStepIndex + step.progress) / totalSteps
        : 0.0;
    context.read<ChatState>().updateExportBar(
          stepLabel: step.label,
          infoText: '${_currentStepIndex + 1} / $totalSteps',
          progress: overallProgress,
        );
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
    final accountId = widget.target.accountId;
    if (accountId == null || accountId.isEmpty) return;

    if (_currentStepIndex < _exportSteps.length) {
      setState(() {
        _exportSteps[_currentStepIndex].progress = 1.0;
        _exportSteps[_currentStepIndex].info = 'Skipped';
        _showSkipFile = false;
      });
      _resetSkipFileTimer();
    }

    context.read<EngineService>().skipExportFile(accountId, _fileRandomId);
  }

  void _cleanupExportSubscriptions() {
    _progressSub?.cancel();
    _errorSub?.cancel();
    _completeSub?.cancel();
    _skipFileTimer?.cancel();
    context.read<ChatState>().stopExportBar();
  }

  void _triggerTakeoutInvalidError() async {
    _cleanupExportSubscriptions();
    await _showExportInformBox(
      'Sorry, you started a new data export, so this data export has been canceled.',
    );
    if (mounted) _closePanel();
  }

  void _triggerTakeoutInitDelayError(
      int hoursRemaining, DateTime availableAt) async {
    _cleanupExportSubscriptions();
    final engine = context.read<EngineService>();
    final accountId = widget.target.accountId ?? '';
    // Persist the available-at time and (re)arm the suggestion timer engine-side
    // (Session::suggestStartExport). The engine stores this in its own file, so
    // we must NOT also write it through saveExportSettings — that would clobber
    // the whole export-settings map with a single key.
    engine.callGeneric(accountId, 'SuggestStartExport', {
      'availableAt': availableAt.millisecondsSinceEpoch,
    }).catchError((_) {});
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final hoursText = hoursRemaining <= 0
        ? 'less than an hour'
        : '$hoursRemaining hour${hoursRemaining == 1 ? '' : 's'}';
    final hour = availableAt.hour;
    final minute = availableAt.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final date =
        '${months[availableAt.month - 1]} ${availableAt.day}, ${availableAt.year} at $hour12:$minute $ampm';
    await _showExportInformBox(
      'For security reasons, you will be able to begin downloading your data in $hoursText. '
      'We have notified all your devices about the export request to make sure it\'s authorized '
      'and give you time to react if it\'s not.\n\n'
      'Please come back on $date and repeat the request using the same device.',
    );
    if (mounted) _closePanel();
  }

  void _triggerDiskError(String path) {
    _cleanupExportSubscriptions();
    setState(() {
      _phase = ExportPhase.error;
      _errorType = _ExportErrorType.diskIo;
      _errorDetail = path;
    });
  }

  void _triggerGenericApiError(int code, String type, String description) {
    _cleanupExportSubscriptions();
    setState(() {
      _phase = ExportPhase.error;
      _errorType = _ExportErrorType.genericApi;
      _errorDetail = '$code: $type\n$description';
    });
  }

  Future<void> _showExportInformBox(String text) async {
    if (!mounted) return;
    final p = PaletteProvider.of(context);
    final boxBg = p.boxBg;
    final boxTextFg = p.boxTextFg;
    final accentColor = p.windowActiveTextFg;
    final closeFg = p.boxTitleAdditionalFg;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
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
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, right: 4),
                    child: IconButton(
                      icon: Icon(Icons.close, size: 18, color: closeFg),
                      onPressed: () => Navigator.of(ctx).pop(),
                      splashRadius: 14,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    text,
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
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: accentColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        child: const Text('OK'),
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

    return Material(
      color: Colors.transparent,
      child: Container(
        width: _exportPanelWidth,
        // Fixed 364×480 for every mode (st::exportPanelSize, export.style:13).
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
              _buildTitleBar(titleColor, subtextColor, borderColor),
              Expanded(
                child: _buildContent(subtextColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar(
      Color titleColor, Color subtextColor, Color borderColor) {
    return GestureDetector(
      onPanUpdate: widget.onTitleDrag != null
          ? (details) => widget.onTitleDrag!(details.delta)
          : null,
      child: Container(
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
      case ExportPhase.completed:
        return _buildProcessingPlaceholder(subtextColor);
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
        context.palette.windowBgActive;
    final shadowColor =
        isDark ? const Color(0xFF0E1621) : const Color(0xFFE0E0E0);

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Builder(builder: (_) {
                final _lvKids = <Widget>[
                  // §29.3.1 Account Data (no header)
                  _buildOptionWithAbout(
                    'Account information',
                    'Your chosen display name, username, phone number and profile photos.',
                    _personalInfo,
                    (v) => _updateSetting(() => _personalInfo = v!),
                    textColor,
                    subtextColor,
                  ),
                  _buildOptionWithAbout(
                    'Contacts list',
                    'If you allow access, contacts are continuously synced with Telegram. You can adjust this in Settings > Privacy & Security on mobile devices.',
                    _contacts,
                    (v) => _updateSetting(() => _contacts = v!),
                    textColor,
                    subtextColor,
                  ),
                  _buildOptionWithAbout(
                    'Story archive',
                    'All stories you posted from Telegram mobile apps.',
                    _stories,
                    (v) => _updateSetting(() => _stories = v!),
                    textColor,
                    subtextColor,
                  ),
                  _buildOptionWithAbout(
                    'Music on Profiles',
                    'All tracks you saved to your playlist.',
                    _profileMusic,
                    (v) => _updateSetting(() => _profileMusic = v!),
                    textColor,
                    subtextColor,
                  ),

                  // §29.3.2 Chats section
                  _buildSectionHeader('Chat export settings', headerColor),
                  _buildChatTypeOption(
                    'Personal chats',
                    _personalChats,
                    (v) => _updateSetting(() => _personalChats = v!),
                    textColor,
                    hasSubOption: false,
                  ),
                  _buildChatTypeOption(
                    'Bot chats',
                    _botChats,
                    (v) => _updateSetting(() => _botChats = v!),
                    textColor,
                    hasSubOption: false,
                  ),
                  _buildChatTypeOption(
                    'Private groups',
                    _privateGroups,
                    (v) => _updateSetting(() => _privateGroups = v!),
                    textColor,
                    hasSubOption: true,
                    subChecked: _privateGroupsOnlyMy,
                    subEnabled: true,
                    onSubChanged: (v) =>
                        _updateSetting(() => _privateGroupsOnlyMy = v!),
                    parentChecked: _privateGroups,
                  ),
                  _buildChatTypeOption(
                    'Private channels',
                    _privateChannels,
                    (v) => _updateSetting(() => _privateChannels = v!),
                    textColor,
                    hasSubOption: true,
                    subChecked: _privateChannelsOnlyMy,
                    subEnabled: true,
                    onSubChanged: (v) =>
                        _updateSetting(() => _privateChannelsOnlyMy = v!),
                    parentChecked: _privateChannels,
                  ),
                  _buildChatTypeOption(
                    'Public groups',
                    _publicGroups,
                    (v) => _updateSetting(() => _publicGroups = v!),
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
                    (v) => _updateSetting(() => _publicChannels = v!),
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
                    'We may store this to display your connected devices in Settings > Privacy & Security > Show all sessions.',
                    _sessions,
                    (v) => _updateSetting(() => _sessions = v!),
                    textColor,
                    subtextColor,
                  ),
                  _buildOptionWithAbout(
                    'Miscellaneous data',
                    'Other types of data not mentioned above (beta).',
                    _otherData,
                    (v) => _updateSetting(() => _otherData = v!),
                    textColor,
                    subtextColor,
                  ),

                  // §29.3.5 Output Format section
                  _buildSectionHeader('Location and format', headerColor),
                  _buildLocationLabel(accentColor, subtextColor),
                  _buildFormatRadio(
                      'Human-readable HTML', _ExportFormat.html, textColor),
                  _buildFormatRadio(
                      'Machine-readable JSON', _ExportFormat.json, textColor),
                  _buildFormatRadio(
                      'Both', _ExportFormat.htmlAndJson, textColor),
                  const SizedBox(height: 8),
                ];
                return ListView.builder(
                  controller: _scrollController,
                padding: EdgeInsets.zero,
                  itemCount: _lvKids.length,
                  itemBuilder: (_, _lvI) => _lvKids[_lvI],
                );
              }),
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
        _buildSectionHeader('Media export settings', headerColor),
        _buildMediaCheckbox('Photos', _mediaPhotos,
            (v) => _updateSetting(() => _mediaPhotos = v!), textColor),
        _buildMediaCheckbox('Videos', _mediaVideo,
            (v) => _updateSetting(() => _mediaVideo = v!), textColor),
        _buildMediaCheckbox('Voice messages', _mediaVoice,
            (v) => _updateSetting(() => _mediaVoice = v!), textColor),
        _buildMediaCheckbox('Video messages', _mediaVideoMessage,
            (v) => _updateSetting(() => _mediaVideoMessage = v!), textColor),
        _buildMediaCheckbox('Stickers', _mediaSticker,
            (v) => _updateSetting(() => _mediaSticker = v!), textColor),
        _buildMediaCheckbox('GIFs', _mediaGif,
            (v) => _updateSetting(() => _mediaGif = v!), textColor),
        _buildMediaCheckbox('Files', _mediaFile,
            (v) => _updateSetting(() => _mediaFile = v!), textColor),
        // Size limit slider
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'Size limit: $_sizeLimitMB MB',
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
              onChanged: (v) => _updateSetting(() => _sizeSliderPos = v),
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
      child: SizedBox(
        height: 21,
        child: Row(
          children: [
            Text('Download path: ', style: TextStyle(fontSize: 13, color: subtextColor)),
            Expanded(
              child: GestureDetector(
                onTap: _pickExportFolder,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Text(
                    _displayExportLocation,
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
            ),
          ],
        ),
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
              onChanged: (v) => _updateSetting(() => _format = v!),
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
            onPressed: _closePanel,
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
    final accentColor =
        context.palette.windowBgActive;
    final shadowColor =
        isDark ? const Color(0xFF0E1621) : const Color(0xFFE0E0E0);

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Builder(builder: (_) {
                final _lvKids = <Widget>[
                  // Single-peer mode adds media options directly with NO header —
                  // AyuGram setupMediaOptions calls addMediaOptions(container)
                  // without addHeader when _singlePeerId != 0; the
                  // "Media export settings" header only exists on the full-export
                  // path (export_view_settings.cpp:218-223).
                  _buildMediaCheckbox('Photos', _mediaPhotos,
                      (v) => _updateSetting(() => _mediaPhotos = v!), textColor),
                  _buildMediaCheckbox('Videos', _mediaVideo,
                      (v) => _updateSetting(() => _mediaVideo = v!), textColor),
                  _buildMediaCheckbox('Voice messages', _mediaVoice,
                      (v) => _updateSetting(() => _mediaVoice = v!), textColor),
                  _buildMediaCheckbox('Video messages', _mediaVideoMessage,
                      (v) => _updateSetting(() => _mediaVideoMessage = v!), textColor),
                  _buildMediaCheckbox('Stickers', _mediaSticker,
                      (v) => _updateSetting(() => _mediaSticker = v!), textColor),
                  _buildMediaCheckbox('GIFs', _mediaGif,
                      (v) => _updateSetting(() => _mediaGif = v!), textColor),
                  _buildMediaCheckbox('Files', _mediaFile,
                      (v) => _updateSetting(() => _mediaFile = v!), textColor),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('Size limit: $_sizeLimitMB MB',
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
                        onChanged: (v) => _updateSetting(() => _sizeSliderPos = v),
                      ),
                    ),
                  ),
                  _buildCombinedFormatLocation(accentColor, subtextColor),
                  _buildDateRangeFilter(accentColor, subtextColor),
                  const SizedBox(height: 8),
                ];
                return ListView.builder(
                  controller: _scrollController,
                padding: EdgeInsets.zero,
                  itemCount: _lvKids.length,
                  itemBuilder: (_, _lvI) => _lvKids[_lvI],
                );
              }),
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
    // AyuGram combined label: lng_export_option_format_location =
    // "Format: {format}, Path: {path}" (lang.strings:6858). The format name is
    // "HTML"/"JSON"/lng_export_option_html_and_json ("Both")
    // (export_view_settings.cpp:366-370).
    final formatName = switch (_format) {
      _ExportFormat.html => 'HTML',
      _ExportFormat.json => 'JSON',
      _ExportFormat.htmlAndJson => 'Both',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
      child: Wrap(
        children: [
          Text('Format: ',
              style: TextStyle(fontSize: 13, color: subtextColor)),
          GestureDetector(
            onTap: () async {
              final chosen = await _showChooseFormatBox();
              if (chosen != null) _updateSetting(() => _format = chosen);
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
          Text(', Path: ', style: TextStyle(fontSize: 13, color: subtextColor)),
          GestureDetector(
            onTap: _pickExportFolder,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Text(
                _displayExportLocation,
                style: TextStyle(
                  fontSize: 13,
                  color: accentColor,
                  decoration: TextDecoration.underline,
                  decorationColor: accentColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // AyuGram langDayOfMonthFull (lang_keys.cpp:92-105): full month name, with the
  // year shown only when the date is not "near" the current year
  // (langDateMaybeWithYear, lang_keys.cpp:21-52). lng_month_day_year =
  // "{month} {day}, {year}", lng_month_day = "{month} {day}".
  String _formatDateLabel(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final month = months[date.month - 1];
    return _dateNeedsYear(date)
        ? '$month ${date.day}, ${date.year}'
        : '$month ${date.day}';
  }

  bool _dateNeedsYear(DateTime date) {
    final now = DateTime.now();
    final year = date.year;
    final month = date.month;
    final currentYear = now.year;
    final currentMonth = now.month;
    if (year == currentYear) return false;
    bool yearMuchGreater(int y, int o) => y > o + 1;
    bool monthMuchGreater(int y, int m, int oy, int om) =>
        (y == oy + 1) && (m + 12 > om + 3);
    return yearMuchGreater(year, currentYear) ||
        yearMuchGreater(currentYear, year) ||
        monthMuchGreater(year, month, currentYear, currentMonth) ||
        monthMuchGreater(currentYear, currentMonth, year, month);
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

  // AyuGram applies the kOffset (600s) clamp to the field being edited, not
  // always to `till` (export_view_settings.cpp:527-588):
  //  - editing the from-time: if the new `from` lands at/after `till`, move
  //    `from` BACKWARD to `till - kOffset` (singlePeerFrom = singlePeerTill - kOffset).
  //  - editing the till-date / till-time: if the new `till` lands at/before
  //    `from`, move `till` FORWARD to `from + kOffset`.
  //  - editing the from-date applies no clamp: the calendar maxDate already
  //    bounds from-date <= till-date, and a date pick resets the time to
  //    start-of-day (date.startOfDay()), so `from <= till` always holds.
  // Each clamp only runs when the opposite endpoint is set (non-null), mirroring
  // the `&& singlePeerTill` / `&& singlePeerFrom` guards.
  void _enforceFromTimeOffset() {
    if (_fromDate == null || _tillDate == null) return;
    final from = _combineDateAndTime(_fromDate!, _fromTimeSeconds);
    final till = _combineDateAndTime(_tillDate!, _tillTimeSeconds);
    if (from.difference(till).inSeconds >= 0) {
      final adjusted = till.subtract(const Duration(seconds: _kOffset));
      _fromDate = DateTime(adjusted.year, adjusted.month, adjusted.day);
      _fromTimeSeconds = adjusted.hour * 3600 + adjusted.minute * 60;
    }
  }

  void _enforceTillOffset() {
    if (_fromDate == null || _tillDate == null) return;
    final from = _combineDateAndTime(_fromDate!, _fromTimeSeconds);
    final till = _combineDateAndTime(_tillDate!, _tillTimeSeconds);
    if (till.difference(from).inSeconds <= 0) {
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
          Text('From: ', style: TextStyle(fontSize: 13, color: subtextColor)),
          GestureDetector(
            onTap: () async {
              final picked = await _showCalendarBox(
                initialDate: _fromDate,
                minDate: _telegramLaunchDate,
                maxDate: _tillDate ?? DateTime.now(),
                resetLabel: 'Reset',
              );
              if (picked != null) {
                setState(() {
                  if (picked.isReset) {
                    _fromDate = null;
                  } else {
                    // AyuGram date pick = date.startOfDay(); no offset clamp.
                    _fromDate = picked.date;
                    _fromTimeSeconds = 0;
                  }
                });
              }
            },
            child: Text(
              _fromDate != null
                  ? _formatDateLabel(_fromDate!)
                  : 'the oldest message',
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
                    _enforceFromTimeOffset();
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
          Text(', to: ', style: TextStyle(fontSize: 13, color: subtextColor)),
          GestureDetector(
            onTap: () async {
              final picked = await _showCalendarBox(
                initialDate: _tillDate,
                minDate: _fromDate ?? _telegramLaunchDate,
                maxDate: DateTime.now(),
                resetLabel: 'Reset',
              );
              if (picked != null) {
                setState(() {
                  if (picked.isReset) {
                    _tillDate = null;
                  } else {
                    // AyuGram date pick = date.startOfDay(), then clamp till forward.
                    _tillDate = picked.date;
                    _tillTimeSeconds = 0;
                    _enforceTillOffset();
                  }
                });
              }
            },
            child: Text(
              _tillDate != null ? _formatDateLabel(_tillDate!) : 'present',
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
                    _enforceTillOffset();
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

  Future<T?> _showAbovePanel<T>(Widget Function(void Function(T?) onResult) builder) {
    final completer = Completer<T?>();
    final panelEntry = _ExportPanelController._entry;
    late OverlayEntry barrierEntry;
    late OverlayEntry contentEntry;

    void close(T? result) {
      contentEntry.remove();
      barrierEntry.remove();
      if (!completer.isCompleted) completer.complete(result);
    }

    barrierEntry = OverlayEntry(
      builder: (_) => GestureDetector(
        onTap: () => close(null),
        behavior: HitTestBehavior.opaque,
        child: const SizedBox.expand(),
      ),
    );

    contentEntry = OverlayEntry(
      builder: (_) => builder(close),
    );

    final overlay = Overlay.of(context);
    if (panelEntry != null) {
      overlay.insert(barrierEntry, above: panelEntry);
    } else {
      overlay.insert(barrierEntry);
    }
    overlay.insert(contentEntry, above: barrierEntry);

    return completer.future;
  }

  Future<_CalendarResult?> _showCalendarBox({
    DateTime? initialDate,
    required DateTime minDate,
    required DateTime maxDate,
    String? resetLabel,
  }) {
    return _showAbovePanel<_CalendarResult>((onResult) => _CalendarBox(
      initialDate: initialDate,
      minDate: minDate,
      maxDate: maxDate,
      resetLabel: resetLabel,
      onResult: onResult,
    ));
  }

  Future<int?> _showChooseTimeBox(int currentSeconds) {
    return _showAbovePanel<int>((onResult) => _ChooseTimeBox(
      initialSeconds: currentSeconds,
      onResult: onResult,
    ));
  }

  Future<_ExportFormat?> _showChooseFormatBox() {
    return _showAbovePanel<_ExportFormat>((onResult) => _ChooseFormatBox(
      current: _format,
      onResult: onResult,
    ));
  }

  Widget _buildProcessingPlaceholder(Color subtextColor) {
    final activeFg = context.palette.mediaPlayerActiveFg;
    final inactiveFg = context.palette.mediaPlayerInactiveFg;
    final attentionFg = context.palette.attentionButtonFg;
    final boldFg = context.palette.windowBoldFg;
    final subFg = context.palette.windowSubTextFg;
    final linkColor = context.palette.windowBgActive;

    // AyuGram's ProgressWidget shows a FIXED set of rows that update in place —
    // 2 for single-peer, 3 for full export: a "main" step row, the current
    // entity row, and a per-file byte-download row (FormatDownloadText). Rows
    // padded to requiredRows render blank so the height stays constant.
    // (export_view_progress.cpp + export_view_content.cpp ContentFromState)
    final rows = _buildProgressRows();

    final aboutText = _exportDone
        // lng_export_about_done / lng_export_progress
        ? 'Your data was successfully exported.'
        : 'You can close this window now. Please don\'t quit Telegram until the data export is completed.';

    final rowKids = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) rowKids.add(const SizedBox(height: 10));
      rowKids.add(
          _buildProgressRow(rows[i], boldFg, subFg, activeFg, inactiveFg));
    }

    return Column(
      children: [
        const SizedBox(height: 10),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...rowKids,
                // "Skip this file" link — appears after a file has been on a
                // download for 5s (lng_export_skip_file).
                if (!_exportDone)
                  SizedBox(
                    height: 28,
                    child: AnimatedOpacity(
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
                                'Skip this file',
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
                  ),
                // About paragraph (exportAboutPadding margins(22,10,22,0)).
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Align(
                      key: ValueKey(_exportDone),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        aboutText,
                        style: TextStyle(fontSize: 14, color: subtextColor),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Bottom button — "Stop" while running, "Show my data" when finished,
        // centered with a 30px bottom margin (exportCancelBottom).
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 30),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _exportDone
                ? SizedBox(
                    key: const ValueKey('done'),
                    width: 200,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: () {
                        _openExportFolder();
                        _closePanel();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: activeFg,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                        padding: const EdgeInsets.only(top: 12),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Show my data'),
                    ),
                  )
                : SizedBox(
                    key: const ValueKey('stop'),
                    width: 200,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _handleClose,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: attentionFg,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                        padding: const EdgeInsets.only(top: 12),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Stop'),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  /// Builds the fixed set of progress rows, mirroring AyuGram ContentFromState:
  /// single-peer → [entity, bytes]; full → [main, entity, bytes]. Empty trailing
  /// rows are kept (blank) so the layout height stays constant, matching
  /// AyuGram's requiredRows padding (export_view_content.cpp:163-166).
  List<_ProgressRow> _buildProgressRows() {
    if (_exportDone) {
      // FinishedState rows: lng_export_finished / lng_export_total_amount /
      // lng_export_total_size, all full-bar (export_view_content.cpp:170-193).
      return [
        const _ProgressRow(label: 'Data export completed.', progress: 1.0),
        _ProgressRow(
            // AyuGram lng_export_total_amount fills {amount} with a plain
            // QString::number — no thousands grouping (export_view_content.cpp:181).
            label: 'Total files: $_totalFiles',
            progress: 1.0),
        _ProgressRow(
            label: 'Total size: ${_formatSize(_totalSizeBytes)}',
            progress: 1.0),
      ];
    }

    final steps = _exportSteps;
    final totalSteps = steps.length;
    final curIdx =
        totalSteps == 0 ? 0 : _currentStepIndex.clamp(0, totalSteps - 1);
    final cur =
        totalSteps == 0 ? _ExportStepInfo(label: '') : steps[curIdx];
    final overall = totalSteps > 0
        ? ((curIdx + cur.progress) / totalSteps).clamp(0.0, 1.0)
        : 0.0;

    final hasBytes = _bytesCount > 0;
    final byteRow = _ProgressRow(
      label: hasBytes ? _bytesName : '',
      info: hasBytes ? _formatDownloadText(_bytesLoaded, _bytesCount) : '',
      progress: hasBytes ? (_bytesLoaded / _bytesCount).clamp(0.0, 1.0) : 0.0,
      empty: !hasBytes,
    );

    if (_isPerChat) {
      // Single-peer: [current-chat entity row, byte row] (no "main" row —
      // ContentFromState omits pushMain when entityCount == 1).
      return [
        _ProgressRow(
          label: widget.target.chatTitle ?? cur.label,
          info: _entityInfo.isNotEmpty ? _entityInfo : cur.info,
          progress: _entityProgress > 0 ? _entityProgress : cur.progress,
        ),
        byteRow,
      ];
    }

    // Full export: [main step row, current-entity row, byte row].
    final entityText = _entityInfo;
    return [
      _ProgressRow(
        label: cur.label,
        info: totalSteps > 0 ? '${curIdx + 1} / $totalSteps' : '',
        progress: overall,
      ),
      _ProgressRow(
        label: entityText,
        progress: cur.progress,
        empty: entityText.isEmpty,
      ),
      byteRow,
    ];
  }

  /// One ProgressWidget::Row: label (left, 14 semibold windowBoldFg) + info
  /// (right, 14 windowSubTextFg) with a 3px progress bar pinned to the bottom
  /// (exportProgressWidth, fg=exportProgressFg, bg=exportProgressBg). [empty]
  /// rows render as blank fixed-height padding to keep the layout constant.
  Widget _buildProgressRow(_ProgressRow row, Color boldFg, Color subFg,
      Color activeFg, Color inactiveFg) {
    if (row.empty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(22, 10, 22, 10),
        child: SizedBox(height: 30),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
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
                      row.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: boldFg,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (row.info.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      row.info,
                      style: TextStyle(fontSize: 14, color: subFg),
                    ),
                  ],
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
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        width: constraints.maxWidth *
                            row.progress.clamp(0.0, 1.0),
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
    );
  }

  /// Port of Ui::FormatTextWithReadyAndTotal + lng_save_downloaded
  /// ("{ready} / {total} {mb}") — format_values.cpp:24-50. e.g. "1.2 / 5.0 MB".
  String _formatDownloadText(int ready, int total) {
    String readyStr, totalStr, unit;
    if (total >= 1024 * 1024) {
      final r = ready * 10 ~/ (1024 * 1024);
      final t = total * 10 ~/ (1024 * 1024);
      readyStr = '${r ~/ 10}.${r % 10}';
      totalStr = '${t ~/ 10}.${t % 10}';
      unit = 'MB';
    } else if (total >= 1024) {
      readyStr = '${ready ~/ 1024}';
      totalStr = '${total ~/ 1024}';
      unit = 'KB';
    } else {
      readyStr = '$ready';
      totalStr = '$total';
      unit = 'B';
    }
    return '$readyStr / $totalStr $unit';
  }

  // AyuGram FormatSizeText (format_values.cpp:54-68): no GB tier — anything
  // >= 1 MB renders as "X.Y MB" (a 2 GB export becomes "2048.0 MB") — and the
  // tenths are truncated via integer math, never rounded.
  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      final tenthMb = bytes * 10 ~/ (1024 * 1024);
      return '${tenthMb ~/ 10}.${tenthMb % 10} MB';
    }
    if (bytes >= 1024) {
      final tenthKb = bytes * 10 ~/ 1024;
      return '${tenthKb ~/ 10}.${tenthKb % 10} KB';
    }
    return '$bytes B';
  }

  Widget _buildErrorPlaceholder(Color subtextColor) {
    final errorColor = context.palette.boxTextFgError;

    final String errorText;
    if (_errorType == _ExportErrorType.diskIo) {
      errorText =
          'Disk Error happened :(\nCould not write path:\n$_errorDetail';
    } else {
      errorText = 'API Error happened :(\n$_errorDetail';
    }

    // AyuGram showCriticalError: a single top-aligned error FlatLabel
    // (st::exportErrorLabel — minWidth 175, align top, textFg boxTextFgError),
    // top-padded by panelHeight/4, with NO buttons — there is no in-panel
    // retry-to-settings path; the panel stays put (setHideOnDeactivate(false))
    // and is dismissed only via the title-bar close (X).
    // (export_view_panel_controller.cpp:264-279, export.style:43-47)
    const topPad = _exportPanelHeight / 4;

    return Padding(
      padding: EdgeInsets.only(top: topPad),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 175),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              errorText,
              style: TextStyle(fontSize: 14, color: errorColor),
              textAlign: TextAlign.center,
            ),
          ),
        ),
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
  final void Function(_CalendarResult?) onResult;

  const _CalendarBox({
    this.initialDate,
    required this.minDate,
    required this.maxDate,
    this.resetLabel,
    required this.onResult,
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
        context.palette.windowBgActive;

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
                      .map((d) => Expanded(
                            child: SizedBox(
                              height: 30,
                              child: Center(
                                child: Text(d,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: subtextColor,
                                        fontWeight: FontWeight.w500)),
                              ),
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
                        onPressed: () => widget.onResult(const _CalendarResult(isReset: true)),
                        style: TextButton.styleFrom(
                          foregroundColor: accentColor,
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                        child: Text(widget.resetLabel!),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => widget.onResult(null),
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
    const cellHeight = 38.0;
    const selectedSize = 32.0;

    final rows = <Widget>[];
    var day = 1;
    final now = DateTime.now();

    for (var row = 0; row < 6 && day <= daysInMonth; row++) {
      final cells = <Widget>[];
      for (var col = 0; col < 7; col++) {
        final cellIndex = row * 7 + col;
        if (cellIndex < offset || day > daysInMonth) {
          cells.add(Expanded(child: SizedBox(height: cellHeight)));
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
          final isToday = now.year == _year &&
              now.month == _month &&
              now.day == thisDay;

          cells.add(
            Expanded(
              child: GestureDetector(
                onTap: isDisabled
                    ? null
                    : () {
                        widget.onResult(_CalendarResult(date: date));
                      },
                child: SizedBox(
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
  final void Function(int?) onResult;
  const _ChooseTimeBox({required this.initialSeconds, required this.onResult});

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
        context.palette.windowBgActive;

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
                  // AyuGram reuses lng_settings_ttl_after_custom for the custom
                  // time box title (export_view_settings.cpp:508).
                  'Set Custom Time',
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
                      onPressed: () => widget.onResult(null),
                      style: TextButton.styleFrom(
                        foregroundColor: subtextColor,
                        textStyle: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: () => widget.onResult(_currentSeconds),
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
  final void Function(_ExportFormat?) onResult;
  const _ChooseFormatBox({required this.current, required this.onResult});

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
        context.palette.windowBgActive;

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
                  // AyuGram lng_export_option_choose_format (lang.strings:6859).
                  'Choose export format',
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
                  'Both', _ExportFormat.htmlAndJson, textColor),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 14, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => widget.onResult(null),
                      style: TextButton.styleFrom(
                        foregroundColor: subtextColor,
                        textStyle: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: () => widget.onResult(_selected),
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

class _ExportSuggestBox extends StatefulWidget {
  final String? accountId;

  const _ExportSuggestBox({this.accountId});

  @override
  State<_ExportSuggestBox> createState() => _ExportSuggestBoxState();
}

class _ExportSuggestBoxState extends State<_ExportSuggestBox> {
  @override
  void initState() {
    super.initState();
    try {
      // Showing the box consumes the suggestion: cancel the engine-side timer and
      // clear the persisted available-at so it isn't re-suggested (mirrors
      // ClearSuggestStart, which SuggestStart calls before showing the box).
      final engine = context.read<EngineService>();
      engine.callGeneric(
        widget.accountId ?? '', 'ClearExportSuggestion', {},
      ).catchError((_) {});
    } catch (e) {
      Debug.log('chat_export', 'final engine = context.read<EngineService>(): $e');
    }
  }

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
                'Data export ready',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'You can now download the data you requested. Start exporting data?',
                style: TextStyle(fontSize: 14, color: textColor, height: 1.4),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'Not now',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      final overlay = Overlay.maybeOf(context) ??
                          Navigator.maybeOf(context)?.overlay;
                      Navigator.of(context).pop();
                      if (overlay != null) {
                        showExportPanelWithOverlay(
                          overlay,
                          ExportTarget(
                            mode: ExportMode.full,
                            accountId: widget.accountId,
                          ),
                        );
                      }
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
