import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/telegram_palette.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../utils/debug.dart';
import 'confirm_box.dart';
import 'telegram_tooltip.dart';

enum CallPanelState {
  incoming,
  connecting,
  exchangingKeys,
  waiting,
  requesting,
  hangingUp,
  ended,
  failed,
  ringing,
  busy,
  active,
  waitingUserConfirmation,
}

String callPanelStateLabel(CallPanelState state, {bool isVideo = false}) {
  return switch (state) {
    CallPanelState.incoming => isVideo ? 'incoming video call...' : 'is calling you...',
    CallPanelState.connecting => 'connecting...',
    CallPanelState.exchangingKeys => 'exchanging encryption keys...',
    CallPanelState.waiting => 'waiting...',
    CallPanelState.requesting => 'requesting...',
    CallPanelState.hangingUp => 'hanging up...',
    CallPanelState.ended => 'call ended',
    CallPanelState.failed => 'failed to connect',
    CallPanelState.ringing => 'ringing...',
    CallPanelState.busy => 'line busy',
    CallPanelState.active => '',
    CallPanelState.waitingUserConfirmation => 'waiting...',
  };
}

class ConferenceInviteParticipant {
  final String name;
  final String avatarUrl;
  const ConferenceInviteParticipant({required this.name, this.avatarUrl = ''});
}

class CallPanelInfo {
  final String callerId;
  final String callerName;
  final String callerAvatarUrl;
  final bool isVideo;
  final CallPanelState state;
  final bool isRemoteMuted;
  final bool isRemoteLowBattery;
  final bool isFullscreen;
  final bool isScreenSharing;
  final bool isMuted;
  final bool isCameraOn;
  final bool isRemoteVideoActive;
  final int signalQuality;
  final List<String> fingerprintEmoji;
  final String callId;
  final DateTime? callStartTime;
  final bool needRating;
  final bool isConferenceInvite;
  final List<ConferenceInviteParticipant> conferenceParticipants;
  final int conferenceParticipantCount;
  final bool conferenceSupported;

  const CallPanelInfo({
    required this.callerId,
    required this.callerName,
    this.callerAvatarUrl = '',
    this.isVideo = false,
    this.state = CallPanelState.incoming,
    this.isRemoteMuted = false,
    this.isRemoteLowBattery = false,
    this.isFullscreen = false,
    this.isScreenSharing = false,
    this.isMuted = false,
    this.isCameraOn = false,
    this.isRemoteVideoActive = false,
    this.signalQuality = -1,
    this.fingerprintEmoji = const [],
    this.callId = '',
    this.callStartTime,
    this.needRating = false,
    this.isConferenceInvite = false,
    this.conferenceParticipants = const [],
    this.conferenceParticipantCount = 0,
    this.conferenceSupported = false,
  });
}

class CallPanel extends StatefulWidget {
  final CallPanelInfo info;
  final VoidCallback? onDecline;
  final VoidCallback? onAccept;
  final VoidCallback? onHangup;
  final VoidCallback? onClose;
  final VoidCallback? onRedial;
  final void Function(bool video)? onStartCall;
  final Widget? remoteVideoWidget;
  final Widget? selfVideoWidget;

  const CallPanel({
    super.key,
    required this.info,
    this.onDecline,
    this.onAccept,
    this.onHangup,
    this.onClose,
    this.onRedial,
    this.onStartCall,
    this.remoteVideoWidget,
    this.selfVideoWidget,
  });

  static const defaultWidth = 720.0;
  static const defaultHeight = 540.0;
  static const minWidth = 380.0;
  static const minHeight = 520.0;

  @override
  State<CallPanel> createState() => _CallPanelState();
}

class _CallPanelState extends State<CallPanel> with TickerProviderStateMixin {
  late AnimationController _controlsFadeController;
  Timer? _durationTimer;
  Timer? _controlsHideTimer;
  Timer? _soundPeakTimer;
  // Scoped to the answer button's outer ripple only — mirrors AyuGram's
  // _updateOuterRippleTimer (kSoundSampleMs=100ms) which repaints just the
  // ripple, never the whole panel. Driven via a ValueNotifier so the 100ms
  // sound-peak sampling no longer rebuilds the userpic/name/status/buttons tree.
  final ValueNotifier<double> _soundPeak = ValueNotifier<double>(0.0);
  final ValueNotifier<int> _durationNotifier = ValueNotifier<int>(0);
  DateTime? _callStartTime;
  bool _avatarFileExists = false;
  bool _controlsVisible = true;
  bool _isMuted = false;
  bool _isCameraOn = false;
  String _selectedCameraDevice = 'Default';
  String _selectedMicDevice = 'Default';
  String _selectedOutputDevice = 'Default';
  List<String> _cameraDevices = ['Default'];
  List<String> _micDevices = ['Default'];
  List<String> _outputDevices = ['Default'];

  static const _kHideControlsFullscreen = Duration(milliseconds: 5000);
  static const _kHideControlsMouseLeave = Duration(milliseconds: 2000);

  @override
  void initState() {
    super.initState();
    _isMuted = widget.info.isMuted;
    _isCameraOn = widget.info.isCameraOn;
    _controlsFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      value: 1.0,
    );
    _cacheAvatarFileExists();
    _enumerateDevices();
    if (widget.info.state == CallPanelState.incoming ||
        widget.info.state == CallPanelState.ringing) {
      _startSoundPeakPolling();
    }
    if (widget.info.state == CallPanelState.active) {
      _startDurationTimer();
      if (widget.info.isFullscreen) {
        _scheduleControlsHide(_kHideControlsFullscreen);
      }
    }
  }

  Future<void> _enumerateDevices() async {
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    List<String> cameras = [];
    List<String> inputs = [];
    List<String> outputs = [];
    try { cameras = await engine.getAudioDevices(accountId, 'camera'); } catch (e) {
      Debug.log('call_panel', 'cameras = await engine.getAudioDevices(accountId, \'camera\'): $e');
    }
    try { inputs = await engine.getAudioDevices(accountId, 'input'); } catch (e) {
      Debug.log('call_panel', 'inputs = await engine.getAudioDevices(accountId, \'input\'): $e');
    }
    try { outputs = await engine.getAudioDevices(accountId, 'output'); } catch (e) {
      Debug.log('call_panel', 'outputs = await engine.getAudioDevices(accountId, \'output\'): $e');
    }
    if (mounted) {
      setState(() {
        _cameraDevices = ['Default', ...cameras];
        _micDevices = ['Default', ...inputs];
        _outputDevices = ['Default', ...outputs];
      });
    }
  }

  @override
  void didUpdateWidget(CallPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.info.isMuted != widget.info.isMuted) {
      _isMuted = widget.info.isMuted;
    }
    if (oldWidget.info.isCameraOn != widget.info.isCameraOn) {
      _isCameraOn = widget.info.isCameraOn;
    }
    if (oldWidget.info.callerAvatarUrl != widget.info.callerAvatarUrl ||
        oldWidget.info.callerId != widget.info.callerId) {
      _cacheAvatarFileExists();
    }
    final isIncoming = widget.info.state == CallPanelState.incoming ||
        widget.info.state == CallPanelState.ringing;
    final wasIncoming = oldWidget.info.state == CallPanelState.incoming ||
        oldWidget.info.state == CallPanelState.ringing;
    if (isIncoming && !wasIncoming) {
      _startSoundPeakPolling();
    } else if (!isIncoming && wasIncoming) {
      _stopSoundPeakPolling();
    }
    if (widget.info.state == CallPanelState.active &&
        oldWidget.info.state != CallPanelState.active) {
      _startDurationTimer();
      if (widget.info.isFullscreen) {
        _scheduleControlsHide(_kHideControlsFullscreen);
      }
    }
    if (widget.info.state != CallPanelState.active) {
      _durationTimer?.cancel();
      _durationTimer = null;
      _showControls();
    }
  }

  void _cacheAvatarFileExists() {
    final url = widget.info.callerAvatarUrl;
    if (url.isNotEmpty) {
      File(url).exists().then((exists) {
        if (mounted && _avatarFileExists != exists) {
          setState(() => _avatarFileExists = exists);
        }
      });
    } else {
      _avatarFileExists = false;
    }
  }

  @override
  void dispose() {
    _controlsFadeController.dispose();
    _durationNotifier.dispose();
    _soundPeak.dispose();
    _durationTimer?.cancel();
    _controlsHideTimer?.cancel();
    _soundPeakTimer?.cancel();
    super.dispose();
  }

  void _startSoundPeakPolling() {
    _soundPeakTimer?.cancel();
    _soundPeakTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _pollSoundPeak();
    });
  }

  void _stopSoundPeakPolling() {
    _soundPeakTimer?.cancel();
    _soundPeakTimer = null;
    _soundPeak.value = 0.0;
  }

  Future<void> _pollSoundPeak() async {
    if (!mounted) return;
    try {
      final engine = context.read<EngineService>();
      final accountId = context.read<AppState>().activeAccountId;
      final peak = await engine.getCallSoundPeak(accountId, widget.info.callId);
      // Scoped update: only the answer button's ripple repaints (via the
      // ValueListenableBuilder in _AnswerButton), not the whole panel tree.
      _soundPeak.value = peak;
    } catch (e) {
      Debug.log('call_panel', 'final engine = context.read<EngineService>(): $e');
    }
  }

  void _scheduleControlsHide(Duration timeout) {
    if (widget.info.state != CallPanelState.active) return;
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(timeout, () {
      if (mounted && widget.info.state == CallPanelState.active) {
        setState(() => _controlsVisible = false);
        _controlsFadeController.reverse();
      }
    });
  }

  void _showControls() {
    _controlsHideTimer?.cancel();
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
      _controlsFadeController.forward();
    }
  }

  void _onMouseMove() {
    if (widget.info.state != CallPanelState.active) return;
    _showControls();
    if (widget.info.isVideo || widget.info.isFullscreen) {
      _scheduleControlsHide(
          widget.info.isFullscreen ? _kHideControlsFullscreen : const Duration(seconds: 2));
    }
  }

  void _startDurationTimer() {
    _callStartTime ??= widget.info.callStartTime ?? DateTime.now();
    final startTime = _callStartTime!;
    _durationNotifier.value = DateTime.now().difference(startTime).inSeconds;
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _durationNotifier.value = DateTime.now().difference(startTime).inSeconds;
      }
    });
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _onScreenShareTap() async {
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    final callId = widget.info.callId;
    if (callId.isEmpty) return;

    if (widget.info.isScreenSharing) {
      await engine.toggleScreenSharing(accountId, callId, false);
      return;
    }
    final result = await showScreenShareChooser(context);
    if (result != null && mounted) {
      await engine.toggleScreenSharing(
        accountId,
        callId,
        true,
        sourceId: result.source.id,
        withAudio: result.withAudio,
      );
    }
  }

  Future<void> _onCameraTap() async {
    final ok = await requestPermissionOrFail(context, PermissionType.camera);
    if (!ok || !mounted) return;
    final callId = widget.info.callId;
    if (callId.isEmpty) return;
    final newCameraOn = !_isCameraOn;
    setState(() => _isCameraOn = newCameraOn);
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    await engine.toggleCamera(accountId, callId, newCameraOn);
  }

  Future<void> _onMuteTap() async {
    final callId = widget.info.callId;
    if (callId.isEmpty) return;
    final newMuted = !_isMuted;
    setState(() => _isMuted = newMuted);
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    await engine.setCallMuted(accountId, callId, newMuted);
  }

  Future<void> _onAddPeopleTap() async {
    if (widget.info.state != CallPanelState.active) return;
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    // Snapshot the current 1:1 call media state so it can be migrated into the
    // conference (AyuGram `migrateConferenceInfo`: muted/video/screen carried over).
    final migrateMuted = _isMuted;
    final migrateCameraOn = _isCameraOn;
    final migrateScreenSharing = widget.info.isScreenSharing;

    final action = await showTelegramBox<String>(
      context: context,
      builder: (ctx) {
        final palette = ctx.palette;
        return TelegramBox(
          title: 'Add People',
          content: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AddPeopleOption(
                  icon: Icons.person_add,
                  title: 'Invite Members',
                  subtitle: 'Invite contacts to a conference call',
                  palette: palette,
                  onTap: () => Navigator.of(ctx).pop('invite'),
                ),
                const SizedBox(height: 4),
                Divider(height: 1, color: palette.boxTextFg.withValues(alpha: 0.1)),
                const SizedBox(height: 4),
                _AddPeopleOption(
                  icon: Icons.link,
                  title: 'Get Shareable Link',
                  subtitle: 'Create a link anyone can use to join',
                  palette: palette,
                  onTap: () => Navigator.of(ctx).pop('link'),
                ),
              ],
            ),
          ),
          buttons: [
            TelegramBoxButton(
              text: 'Cancel',
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        );
      },
    );
    if (action == null || !mounted) return;

    if (action == 'invite') {
      final selectedIds = await showTelegramBox<Set<String>>(
        context: context,
        builder: (ctx) => _InviteContactPicker(
          engine: engine,
          accountId: accountId,
          excludeUserId: widget.info.callerId,
        ),
      );
      if (selectedIds == null || selectedIds.isEmpty || !mounted) return;

      final result = await engine.createConferenceCall(accountId);
      if (result == null || !mounted) return;

      try {
        await engine.joinGroupCall(accountId, result.callId);
      } catch (e) {
        Debug.error('CALL', 'Failed to join conference, aborting upgrade', e);
        return;
      }

      if (widget.info.callId.isNotEmpty) {
        await engine.endCall(accountId, widget.info.callId);
      }

      // Carry the original call's mute / camera / screen-share state into the conference.
      await _migrateCallStateToConference(
        engine, accountId, result.callId,
        muted: migrateMuted,
        cameraOn: migrateCameraOn,
        screenSharing: migrateScreenSharing,
      );

      await engine.inviteToConferenceCall(accountId, result.callId, selectedIds.toList());

      if (mounted) {
        showConfirmBox(
          context,
          title: 'Invitations Sent',
          text: 'Invited ${selectedIds.length} contact${selectedIds.length == 1 ? '' : 's'} to conference call.',
          confirmText: 'Copy Link',
          onConfirm: () {
            Clipboard.setData(ClipboardData(text: result.inviteLink));
          },
        );
      }
    } else if (action == 'link') {
      final result = await engine.createConferenceCall(accountId);
      if (result == null || !mounted) return;

      try {
        await engine.joinGroupCall(accountId, result.callId);
      } catch (e) {
        Debug.error('CALL', 'Failed to join conference, aborting link share', e);
        return;
      }

      if (widget.info.callId.isNotEmpty) {
        await engine.endCall(accountId, widget.info.callId);
      }

      // Carry the original call's mute / camera / screen-share state into the conference.
      await _migrateCallStateToConference(
        engine, accountId, result.callId,
        muted: migrateMuted,
        cameraOn: migrateCameraOn,
        screenSharing: migrateScreenSharing,
      );

      if (!mounted) return;
      showConfirmBox(
        context,
        title: 'Conference Call Created',
        text: 'Share this link to invite others:\n${result.inviteLink}',
        confirmText: 'Copy Link',
        onConfirm: () {
          Clipboard.setData(ClipboardData(text: result.inviteLink));
        },
      );
    }
  }

  // Migrate the original 1:1 call's media state into the freshly-joined conference,
  // mirroring AyuGram's `migrateConferenceInfo` (.muted = muted(),
  // .videoCapture = isSharingVideo() ? ... : nullptr, .videoCaptureScreenId = ...).
  // Applied after the old call ends so the camera / screen-capture device is free.
  Future<void> _migrateCallStateToConference(
    EngineService engine,
    String accountId,
    String confCallId, {
    required bool muted,
    required bool cameraOn,
    required bool screenSharing,
  }) async {
    if (confCallId.isEmpty) return;
    await engine.setCallMuted(accountId, confCallId, muted);
    if (cameraOn) {
      await engine.toggleCamera(accountId, confCallId, true);
    }
    if (screenSharing) {
      await engine.toggleScreenSharing(accountId, confCallId, true);
    }
  }

  Future<void> _showCameraDeviceMenu(BuildContext btnContext) async {
    final RenderBox box = btnContext.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset(box.size.width / 2, 0));
    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem(enabled: false, child: Text('Camera', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
      for (final cam in _cameraDevices)
        PopupMenuItem(
          value: 'cam_$cam',
          child: Row(
            children: [
              if (cam == _selectedCameraDevice)
                const Icon(Icons.check, size: 16, color: Colors.white70),
              if (cam == _selectedCameraDevice) const SizedBox(width: 8),
              Expanded(child: Text(cam, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
    ];
    final result = await showMenu<String>(
      context: btnContext,
      position: RelativeRect.fromLTRB(offset.dx - 120, offset.dy - 8, offset.dx + 120, offset.dy),
      items: items,
    );
    if (result == null || !mounted) return;
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    if (result.startsWith('cam_')) {
      setState(() => _selectedCameraDevice = result.substring(4));
      engine.setCallAudioDevice(accountId, 'camera', result.substring(4));
    }
  }

  Future<void> _showAudioDeviceMenu(BuildContext btnContext) async {
    final RenderBox box = btnContext.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset(box.size.width / 2, 0));
    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem(enabled: false, child: Text('Output', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
      for (final out in _outputDevices)
        PopupMenuItem(
          value: 'out_$out',
          child: Row(
            children: [
              if (out == _selectedOutputDevice)
                const Icon(Icons.check, size: 16, color: Colors.white70),
              if (out == _selectedOutputDevice) const SizedBox(width: 8),
              Expanded(child: Text(out, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem(enabled: false, child: Text('Microphone', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
      for (final mic in _micDevices)
        PopupMenuItem(
          value: 'mic_$mic',
          child: Row(
            children: [
              if (mic == _selectedMicDevice)
                const Icon(Icons.check, size: 16, color: Colors.white70),
              if (mic == _selectedMicDevice) const SizedBox(width: 8),
              Expanded(child: Text(mic, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
    ];
    final result = await showMenu<String>(
      context: btnContext,
      position: RelativeRect.fromLTRB(offset.dx - 120, offset.dy - 8, offset.dx + 120, offset.dy),
      items: items,
    );
    if (result == null || !mounted) return;
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    if (result.startsWith('out_')) {
      setState(() => _selectedOutputDevice = result.substring(4));
      engine.setCallAudioDevice(accountId, 'output', result.substring(4));
    } else if (result.startsWith('mic_')) {
      setState(() => _selectedMicDevice = result.substring(4));
      engine.setCallAudioDevice(accountId, 'input', result.substring(4));
    }
  }

  // AyuGram paints a radial gradient centered on the userpic, sourced from the
  // peer's color profile (peerColors().colorProfileFor) — NOT from the avatar
  // bitmap. The peer name-color index isn't plumbed to the panel, so we resolve
  // the *default* profile the same way Telegram does for a peer without a custom
  // color: the deterministic peerId→userpic-palette mapping (the very two-tone
  // gradient painted behind the peer's letter-avatar). Darkened for the dark
  // panel so the white controls stay legible: lighter centre (under the userpic)
  // → darker edge, matching ColorProfileSet{edge, center} reversed in updateBrush.
  static const _profileColorRemap = [0, 7, 4, 1, 6, 3, 5];

  List<Color> _profileGradientColors(TelegramPalette palette) {
    final id = widget.info.callerId;
    final numId = int.tryParse(id) ?? id.hashCode.abs();
    final index = _profileColorRemap[numId.abs() % 7];
    final center = _towardLightness(palette.peerUserpicBg(index), 0.34);
    final edge = _towardLightness(palette.peerUserpicBg2(index), 0.20);
    return [center, edge];
  }

  // Pull a peer color toward a target HSL lightness while keeping its hue, so the
  // gradient reads as the peer's color but stays dark enough for the call panel.
  static Color _towardLightness(Color c, double lightness) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness(lightness.clamp(0.0, 1.0))
        .withSaturation((hsl.saturation * 0.85).clamp(0.0, 1.0))
        .toColor();
  }

  Widget _buildUserpic(double size) {
    final url = widget.info.callerAvatarUrl;
    if (url.isNotEmpty && _avatarFileExists) {
      return ClipOval(
        child: Image.file(File(url), width: size, height: size, fit: BoxFit.cover),
      );
    }
    final id = widget.info.callerId;
    final hash = id.hashCode.abs();
    final hue = (hash % 360).toDouble();
    final name = widget.info.callerName;
    final initials = name.isNotEmpty
        ? name.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join()
        : '?';
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: HSLColor.fromAHSL(1.0, hue, 0.5, 0.45).toColor(),
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildConferenceParticipantsRow() {
    final participants = widget.info.conferenceParticipants;
    final totalCount = widget.info.conferenceParticipantCount;
    if (participants.isEmpty && totalCount <= 0) return const SizedBox.shrink();

    final displayCount = participants.length.clamp(0, 3);
    final remaining = totalCount - displayCount;

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < displayCount; i++)
            Padding(
              padding: EdgeInsets.only(left: i > 0 ? 0 : 0),
              child: Transform.translate(
                offset: Offset(i > 0 ? -6.0 * i : 0, 0),
                child: _buildParticipantAvatar(participants[i], 28),
              ),
            ),
          if (remaining > 0)
            Transform.translate(
              offset: Offset(-6.0 * displayCount, 0),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$remaining',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildParticipantAvatar(ConferenceInviteParticipant participant, double size) {
    if (participant.avatarUrl.isNotEmpty) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
        ),
        child: ClipOval(
          child: Image.file(File(participant.avatarUrl), width: size, height: size, fit: BoxFit.cover),
        ),
      );
    }
    final initials = participant.name.isNotEmpty
        ? participant.name.split(' ').where((w) => w.isNotEmpty).take(1).map((w) => w[0].toUpperCase()).join()
        : '?';
    final hue = (participant.name.hashCode.abs() % 360).toDouble();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: HSLColor.fromAHSL(1.0, hue, 0.5, 0.45).toColor(),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(color: Colors.white, fontSize: size * 0.36, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildIncomingState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 3),
        _buildUserpic(160),
        const SizedBox(height: 20),
        Text(
          widget.info.callerName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        if (widget.info.isConferenceInvite)
          _buildConferenceParticipantsRow(),
        Text(
          callPanelStateLabel(widget.info.state, isVideo: widget.info.isVideo),
          style: const TextStyle(
            color: Color(0xAAFFFFFF),
            fontSize: 15,
          ),
        ),
        const Spacer(flex: 4),
        // AyuGram shows the pre-answer Mute + Camera toggles on the incoming
        // screen too (mute toggled visible when !isWaitingUser, camera visible
        // when !_startVideo even while incomingWaiting), flanking Decline +
        // Answer in the single control row — order: Camera, Decline, Answer, Mute
        // (calls_panel.cpp:1407,1421, geometry :1300-1313). Screencast stays
        // hidden while incomingWaiting. The toggles let the callee pre-arm
        // mute/camera before accepting.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CallControlButton(
              icon: _isCameraOn ? Icons.videocam : Icons.videocam_off_outlined,
              label: _isCameraOn ? 'Stop Video' : 'Camera',
              isActive: _isCameraOn,
              onTap: _onCameraTap,
            ),
            const SizedBox(width: 28),
            _CallActionButton(
              icon: Icons.call_end,
              label: 'Decline',
              backgroundColor: const Color(0xFFE53935),
              onTap: widget.onDecline,
            ),
            const SizedBox(width: 28),
            _AnswerButton(
              soundPeak: _soundPeak,
              onTap: widget.onAccept,
              isVideo: widget.info.isVideo,
            ),
            const SizedBox(width: 28),
            _CallControlButton(
              icon: _isMuted ? Icons.mic_off : Icons.mic_outlined,
              label: _isMuted ? 'Unmute' : 'Mute',
              isActive: _isMuted,
              onTap: _onMuteTap,
            ),
          ],
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildConnectingState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasPreview = widget.info.isVideo && widget.selfVideoWidget != null;
        // AyuGram keeps the callee userpic + name + status and places the
        // outgoing self-preview as a small in-body block BELOW them
        // (calls_panel.cpp:1226,1264-1271) — it is NOT a fullscreen self-camera.
        // With a preview present it switches to the callBodyWithPreview layout
        // whose photoSize is 100px (calls.style:57-67).
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 3),
            _buildUserpic(hasPreview ? 100 : 160),
            const SizedBox(height: 20),
            Text(
              widget.info.callerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              callPanelStateLabel(widget.info.state, isVideo: widget.info.isVideo),
              style: const TextStyle(
                color: Color(0xAAFFFFFF),
                fontSize: 15,
              ),
            ),
            if (hasPreview) ...[
              const SizedBox(height: 24),
              _OutgoingPreview(
                videoWidget: widget.selfVideoWidget!,
                containerHeight: constraints.maxHeight,
                innerWidth: constraints.maxWidth - 2 * 12, // 2 * callInnerPadding
              ),
            ],
            const Spacer(flex: 4),
            // AyuGram keeps the Mute + Camera + Screencast (+ Add People) controls
            // visible throughout the outgoing setup states (connecting / ringing /
            // exchangingKeys / waiting / requesting): toggleButton(_mute,
            // !isWaitingUser), toggleButton(_screencast, !(isBusy||isWaitingUser||
            // incomingWaiting)), _camera->setVisible(!_startVideo) — with the big
            // red End Call (hangup) in the middle (calls_panel.cpp:1407-1425). This
            // is the same control row as the active state, so the user can mute /
            // enable camera / screencast while the call is still ringing.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildControlsRow(),
            ),
            const SizedBox(height: 48),
          ],
        );
      },
    );
  }

  // AyuGram formats remote-status strings with `_user->shortName()` (the first
  // name), not the full display name. Approximate shortName by the first
  // whitespace-separated token of the caller's name.
  String get _callerShortName {
    final full = widget.info.callerName.trim();
    if (full.isEmpty) return full;
    final idx = full.indexOf(' ');
    return idx > 0 ? full.substring(0, idx) : full;
  }

  Widget _buildRemotePills() {
    // AyuGram positions the "microphone off" and "battery low" labels in the
    // same slot and hides the low-battery label whenever the mute label is shown
    // (Panel::showRemoteLowBattery: setVisible(!_remoteAudioMute
    // || _remoteAudioMute->isHidden())), so mute takes priority and the two are
    // never displayed together. — calls_panel.cpp:965.
    final Widget pill;
    if (widget.info.isRemoteMuted) {
      pill = _RemoteStatusPill(
        icon: Icons.mic_off,
        text: "$_callerShortName's microphone is off",
      );
    } else if (widget.info.isRemoteLowBattery) {
      pill = _RemoteStatusPill(
        icon: Icons.battery_alert,
        text: "$_callerShortName's battery level is low",
      );
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: pill,
    );
  }

  Widget _buildControlsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CallControlButton(
          icon: widget.info.isScreenSharing
              ? Icons.stop_screen_share_outlined
              : Icons.screen_share_outlined,
          label: widget.info.isScreenSharing ? 'Stop' : 'Screencast',
          isActive: widget.info.isScreenSharing,
          onTap: _onScreenShareTap,
        ),
        _CallControlButton(
          icon: _isCameraOn ? Icons.videocam : Icons.videocam_off_outlined,
          label: _isCameraOn ? 'Stop Video' : 'Camera',
          isActive: _isCameraOn,
          onTap: _onCameraTap,
          showDeviceChevron: true,
          onDeviceChevronTap: _showCameraDeviceMenu,
        ),
        _CallActionButton(
          icon: Icons.call_end,
          label: 'End Call',
          backgroundColor: const Color(0xFFE53935),
          onTap: widget.onHangup,
        ),
        _CallControlButton(
          icon: _isMuted ? Icons.mic_off : Icons.mic_outlined,
          label: _isMuted ? 'Unmute' : 'Mute',
          isActive: _isMuted,
          onTap: _onMuteTap,
          showDeviceChevron: true,
          onDeviceChevronTap: _showAudioDeviceMenu,
        ),
        // AyuGram only shows "Add People" once the server reports the call can be
        // upgraded to a conference (`toggleButton(_addPeople, ... && _conferenceSupported)`).
        if (widget.info.conferenceSupported)
          _CallControlButton(
            icon: Icons.person_add_outlined,
            label: 'Add People',
            onTap: _onAddPeopleTap,
          ),
      ],
    );
  }

  // Mid-panel status line below the caller name (just the call duration).
  // AyuGram keeps the encryption fingerprint + signal bars OUT of this line —
  // they live in a badge pinned to the top-center of the panel (callFingerprintTop).
  Widget _buildStatusRow() {
    return ValueListenableBuilder<int>(
      valueListenable: _durationNotifier,
      builder: (context, seconds, _) => Text(
        _formatDuration(seconds),
        style: const TextStyle(
          color: Color(0xAAFFFFFF),
          fontSize: 15,
        ),
      ),
    );
  }

  // Encryption fingerprint (emoji) + signal-bars badge, pinned to the top-center
  // of the panel (AyuGram `calls_panel.cpp` updateFingerprintGeometry:
  // top = callFingerprintTop (8px), horizontally centered). Returns an empty box
  // when no fingerprint/signal is available yet (e.g. before key exchange).
  Widget _buildFingerprintBadge() {
    final hasFingerprint = widget.info.fingerprintEmoji.length == 4;
    final hasSignal = widget.info.signalQuality >= 0;
    if (!hasFingerprint && !hasSignal) return const SizedBox.shrink();

    // AyuGram CreateFingerprintAndSignalBars (calls_emoji_fingerprint.cpp:
    // 224-309): ONE continuous badge — emoji on the left with a big-radius
    // (height/2) left edge, signal bars on the right with a big-radius right
    // edge, joined by small-radius (roundRadiusSmall = 3px) inner edges and a
    // 2px skip (callFingerprintSignalBarsSkip). Both halves share callBgButton —
    // NOT two separate pills with a 6px gap.
    const badgeBg = Color(0x26FFFFFF); // st::callBgButton (~white @ 0.15 on the dark panel)
    const big = Radius.circular(100);  // height/2 pill cap
    const small = Radius.circular(3);  // st::roundRadiusSmall

    return IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasFingerprint)
            DecoratedBox(
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.only(
                  topLeft: big,
                  bottomLeft: big,
                  topRight: hasSignal ? small : big,
                  bottomRight: hasSignal ? small : big,
                ),
              ),
              child: Padding(
                // callFingerprintPadding: margins(10px, 4px, 8px, 5px).
                padding: const EdgeInsets.fromLTRB(10, 4, 8, 5),
                child: Center(
                  child: _EncryptionFingerprint(
                    emoji: widget.info.fingerprintEmoji,
                    callerName: widget.info.callerName,
                  ),
                ),
              ),
            ),
          if (hasFingerprint && hasSignal)
            const SizedBox(width: 2), // callFingerprintSignalBarsSkip
          if (hasSignal)
            DecoratedBox(
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.only(
                  topLeft: hasFingerprint ? small : big,
                  bottomLeft: hasFingerprint ? small : big,
                  topRight: big,
                  bottomRight: big,
                ),
              ),
              child: Padding(
                // callSignalBarsPadding: margins(8px, 9px, 11px, 5px).
                padding: const EdgeInsets.fromLTRB(8, 9, 11, 5),
                child: Center(
                  child: _SignalBars(quality: widget.info.signalQuality),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Pinned top-center fingerprint badge for use inside the active-state Stacks.
  Widget _buildPinnedFingerprint() {
    return Positioned(
      top: 8, // st::callFingerprintTop
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _controlsFadeController,
        child: Center(child: _buildFingerprintBadge()),
      ),
    );
  }

  Widget _buildActiveVideoState() {
    return MouseRegion(
      onHover: (_) => _onMouseMove(),
      onEnter: (_) => _onMouseMove(),
      onExit: (_) {
        if (widget.info.state == CallPanelState.active) {
          _scheduleControlsHide(_kHideControlsMouseLeave);
        }
      },
      child: GestureDetector(
        onTap: _onMouseMove,
        child: Stack(
          children: [
            Positioned.fill(
              child: widget.remoteVideoWidget!,
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: FadeTransition(
                opacity: _controlsFadeController,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x80000000), Color(0x00000000)],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildUserpic(28),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  widget.info.callerName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildStatusRow(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (widget.info.isRemoteMuted || widget.info.isRemoteLowBattery)
              Positioned(
                left: 0,
                right: 0,
                top: 56,
                child: _buildRemotePills(),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FadeTransition(
                opacity: _controlsFadeController,
                child: Container(
                  padding: const EdgeInsets.only(left: 24, right: 24, bottom: 48, top: 24),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0x80000000), Color(0x00000000)],
                    ),
                  ),
                  child: _buildControlsRow(),
                ),
              ),
            ),
            _buildPinnedFingerprint(),
            if (widget.selfVideoWidget != null)
              _SelfViewBubble(
                videoWidget: widget.selfVideoWidget!,
                mirror: !widget.info.isScreenSharing,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveState() {
    if (widget.remoteVideoWidget != null) {
      return _buildActiveVideoState();
    }
    return MouseRegion(
      onHover: (_) => _onMouseMove(),
      onEnter: (_) => _onMouseMove(),
      onExit: (_) {
        if (widget.info.state == CallPanelState.active) {
          _scheduleControlsHide(_kHideControlsMouseLeave);
        }
      },
      child: GestureDetector(
        onTap: _onMouseMove,
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 3),
                _buildUserpic(160),
                const SizedBox(height: 20),
                Text(
                  widget.info.callerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                _buildStatusRow(),
                _buildRemotePills(),
                const Spacer(flex: 4),
                FadeTransition(
                  opacity: _controlsFadeController,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _buildControlsRow(),
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
            _buildPinnedFingerprint(),
            if (widget.selfVideoWidget != null)
              _SelfViewBubble(
                videoWidget: widget.selfVideoWidget!,
                mirror: !widget.info.isScreenSharing,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 3),
        _buildUserpic(160),
        const SizedBox(height: 20),
        Text(
          widget.info.callerName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          callPanelStateLabel(CallPanelState.busy, isVideo: widget.info.isVideo),
          style: const TextStyle(
            color: Color(0xAAFFFFFF),
            fontSize: 15,
          ),
        ),
        const Spacer(flex: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CallActionButton(
              icon: Icons.close,
              label: 'Close',
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              onTap: widget.onClose,
            ),
            const SizedBox(width: 80),
            _CallActionButton(
              icon: Icons.call,
              label: 'Redial',
              backgroundColor: const Color(0xFF4CAF50),
              onTap: widget.onRedial,
            ),
          ],
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildWaitingConfirmationState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 3),
        _buildUserpic(160),
        const SizedBox(height: 20),
        Text(
          widget.info.callerName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'waiting...',
          style: TextStyle(
            color: Color(0xAAFFFFFF),
            fontSize: 15,
          ),
        ),
        const Spacer(flex: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CallActionButton(
              icon: Icons.close,
              label: 'Cancel',
              backgroundColor: const Color(0xFFE53935),
              onTap: widget.onDecline,
            ),
            const SizedBox(width: 40),
            _CallActionButton(
              icon: Icons.call,
              label: 'Start Call',
              backgroundColor: const Color(0xFF4CAF50),
              onTap: () => widget.onStartCall?.call(false),
            ),
            const SizedBox(width: 40),
            _CallActionButton(
              icon: Icons.videocam,
              label: 'Start Video',
              backgroundColor: const Color(0xFF4CAF50),
              onTap: () => widget.onStartCall?.call(true),
            ),
          ],
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildEndedState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 3),
        _buildUserpic(160),
        const SizedBox(height: 20),
        Text(
          widget.info.callerName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          callPanelStateLabel(widget.info.state, isVideo: widget.info.isVideo),
          style: const TextStyle(
            color: Color(0xAAFFFFFF),
            fontSize: 15,
          ),
        ),
        const Spacer(flex: 4),
        TextButton(
          onPressed: widget.onClose,
          child: const Text(
            'Close',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _profileGradientColors(context.palette);

    Widget content;
    switch (widget.info.state) {
      case CallPanelState.incoming:
        content = _buildIncomingState();
      case CallPanelState.waitingUserConfirmation:
        content = _buildWaitingConfirmationState();
      case CallPanelState.connecting:
      case CallPanelState.exchangingKeys:
      case CallPanelState.waiting:
      case CallPanelState.requesting:
      case CallPanelState.ringing:
        content = _buildConnectingState();
      case CallPanelState.active:
        content = _buildActiveState();
      case CallPanelState.busy:
        content = _buildBusyState();
      case CallPanelState.ended:
      case CallPanelState.failed:
      case CallPanelState.hangingUp:
        content = _buildEndedState();
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: CallPanel.minWidth,
        minHeight: CallPanel.minHeight,
      ),
      child: DecoratedBox(
        // AyuGram QRadialGradient centered on the userpic (calls_panel_background
        // .cpp:142-147), not a top→bottom linear fill. The userpic sits in the
        // upper-centre of the body across the non-video states, so anchor the
        // radial there with a radius that reaches the far corner. colors =
        // [centre(lighter), edge(darker)].
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.0, -0.3),
            radius: 1.3,
            colors: colors,
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: KeyedSubtree(
            key: ValueKey(widget.info.state),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    this.onTap,
    this.size = 44,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: iconSize),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xAAFFFFFF),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _AnswerButton extends StatelessWidget {
  final ValueListenable<double> soundPeak;
  final VoidCallback? onTap;
  final bool isVideo;

  const _AnswerButton({
    required this.soundPeak,
    this.onTap,
    this.isVideo = false,
  });

  @override
  Widget build(BuildContext context) {
    final core = Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        color: Color(0xFF4CAF50),
        shape: BoxShape.circle,
      ),
      child: Icon(
        isVideo ? Icons.videocam : Icons.call,
        color: Colors.white,
        size: 24,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          // Only the outer ripple repaints on each 100ms sound-peak sample —
          // the green core + icon are a const child reused across rebuilds.
          child: ValueListenableBuilder<double>(
            valueListenable: soundPeak,
            child: core,
            builder: (context, peak, child) {
              return CustomPaint(
                painter: _RippleRingPainter(
                  outerValue: peak,
                  color: const Color(0xFF4CAF50),
                ),
                child: child,
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isVideo ? 'Answer Video' : 'Answer',
          style: const TextStyle(
            color: Color(0xAAFFFFFF),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _RippleRingPainter extends CustomPainter {
  final double outerValue;
  final Color color;
  static const double _outerRadius = 12.0;

  _RippleRingPainter({required this.outerValue, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (outerValue <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final outerPixels = outerValue * _outerRadius;
    final rect = Rect.fromCenter(
      center: center,
      width: size.width + outerPixels * 2,
      height: size.height + outerPixels * 2,
    );
    final paint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawOval(rect, paint);
  }

  @override
  bool shouldRepaint(_RippleRingPainter oldDelegate) =>
      oldDelegate.outerValue != outerValue;
}

class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;
  final bool showDeviceChevron;
  final void Function(BuildContext context)? onDeviceChevronTap;

  const _CallControlButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.onTap,
    this.showDeviceChevron = false,
    this.onDeviceChevronTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                if (showDeviceChevron)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: () => onDeviceChevronTap?.call(context),
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.expand_more,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xAAFFFFFF),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _AddPeopleOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final TelegramPalette palette;
  final VoidCallback onTap;

  const _AddPeopleOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, color: palette.windowActiveTextFg, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 14, color: palette.boxTextFg)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: palette.boxTextFg.withValues(alpha: 0.5))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteContactPicker extends StatefulWidget {
  final EngineService engine;
  final String accountId;
  final String excludeUserId;

  const _InviteContactPicker({
    required this.engine,
    required this.accountId,
    this.excludeUserId = '',
  });

  @override
  State<_InviteContactPicker> createState() => _InviteContactPickerState();
}

class _InviteContactPickerState extends State<_InviteContactPicker> {
  List<ContactInfo>? _contacts;
  bool _loading = true;
  final Set<String> _selectedIds = {};
  final _searchController = TextEditingController();
  String _searchQuery = '';
  List<ContactInfo>? _filteredCache;
  String _filteredCacheQuery = '';

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    try {
      final contacts = await widget.engine.getContacts(widget.accountId);
      if (mounted) {
        setState(() {
          _contacts = contacts
              .where((c) => !c.isBot && c.userId != widget.excludeUserId)
              .toList()
            ..sort((a, b) => a.displayName.compareTo(b.displayName));
          _filteredCache = null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ContactInfo> get _filteredContacts {
    final all = _contacts ?? [];
    if (_searchQuery.isEmpty) return all;
    if (_filteredCache != null && _filteredCacheQuery == _searchQuery) {
      return _filteredCache!;
    }
    final q = _searchQuery.toLowerCase();
    _filteredCache = all
        .where((c) =>
            c.displayName.toLowerCase().contains(q) ||
            c.username.toLowerCase().contains(q))
        .toList();
    _filteredCacheQuery = _searchQuery;
    return _filteredCache!;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textColor = p.boxTextFg;
    final subtextColor = p.boxTitleAdditionalFg;
    final accentColor = p.windowBgActive;
    final dividerColor = p.boxDividerBg;

    return Dialog(
      backgroundColor: p.boxBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 364, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.only(left: 24, top: 13),
                child: Text(
                  'Invite to Conference Call',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(fontSize: 14, color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Search',
                    hintStyle: TextStyle(fontSize: 14, color: subtextColor),
                    prefixIcon:
                        Icon(Icons.search, size: 20, color: subtextColor),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF131C26)
                        : const Color(0xFFF0F0F0),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
            ),
            Divider(height: 1, color: dividerColor),
            Expanded(
              child: _loading
                  ? Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: accentColor),
                      ),
                    )
                  : _filteredContacts.isEmpty
                      ? Center(
                          child: Text(
                            _searchQuery.isEmpty
                                ? 'No contacts found'
                                : 'No results',
                            style:
                                TextStyle(fontSize: 14, color: subtextColor),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _filteredContacts.length,
                          itemBuilder: (context, index) {
                            final contact = _filteredContacts[index];
                            final selected =
                                _selectedIds.contains(contact.userId);
                            return _InviteContactRow(
                              contact: contact,
                              selected: selected,
                              textColor: textColor,
                              subtextColor: subtextColor,
                              accentColor: accentColor,
                              onTap: () {
                                setState(() {
                                  if (selected) {
                                    _selectedIds.remove(contact.userId);
                                  } else {
                                    _selectedIds.add(contact.userId);
                                  }
                                });
                              },
                            );
                          },
                        ),
            ),
            Divider(height: 1, color: dividerColor),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(fontSize: 14, color: subtextColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _selectedIds.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(_selectedIds),
                    child: Text(
                      _selectedIds.isEmpty
                          ? 'Invite'
                          : 'Invite (${_selectedIds.length})',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _selectedIds.isEmpty
                            ? subtextColor
                            : accentColor,
                      ),
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

class _InviteContactRow extends StatelessWidget {
  final ContactInfo contact;
  final bool selected;
  final Color textColor;
  final Color subtextColor;
  final Color accentColor;
  final VoidCallback onTap;

  const _InviteContactRow({
    required this.contact,
    required this.selected,
    required this.textColor,
    required this.subtextColor,
    required this.accentColor,
    required this.onTap,
  });

  static final _avatarCache = <String, Uint8List>{};

  // AyuGram's invite rows are PeerListRows that paint the real userpic
  // (calls_group_invite_controller.cpp:83,201). ContactInfo already carries the
  // engine-decoded avatar as base64 — the same field the create-group picker
  // decodes (create_group_wizard.dart:1716) — so render it instead of an
  // initials-only CircleAvatar.
  Widget _buildAvatar() {
    if (contact.avatarB64.isNotEmpty) {
      try {
        final bytes = _avatarCache.putIfAbsent(
            contact.avatarB64, () => base64Decode(contact.avatarB64));
        return CircleAvatar(radius: 20, backgroundImage: MemoryImage(bytes));
      } catch (_) {
        // fall through to initials
      }
    }
    return CircleAvatar(
      radius: 20,
      backgroundColor: accentColor.withValues(alpha: 0.2),
      child: Text(
        contact.displayName.isNotEmpty
            ? contact.displayName[0].toUpperCase()
            : '?',
        style: TextStyle(
          color: accentColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            _buildAvatar(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.displayName,
                    style: TextStyle(fontSize: 14, color: textColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (contact.username.isNotEmpty)
                    Text(
                      '@${contact.username}',
                      style: TextStyle(fontSize: 12, color: subtextColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 24,
              height: 24,
              child: selected
                  ? Icon(Icons.check_circle, color: accentColor, size: 22)
                  : Icon(Icons.radio_button_unchecked,
                      color: subtextColor.withValues(alpha: 0.4), size: 22),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteStatusPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _RemoteStatusPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xAAFFFFFF), size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  color: Color(0xAAFFFFFF),
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EncryptionFingerprint extends StatefulWidget {
  final List<String> emoji;
  final String callerName;

  const _EncryptionFingerprint({required this.emoji, this.callerName = ''});

  @override
  State<_EncryptionFingerprint> createState() => _EncryptionFingerprintState();
}

class _EncryptionFingerprintState extends State<_EncryptionFingerprint>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<List<String>> _carouselSequences;

  static const _kEmojiCount = 4;
  static const _kCarouselCount = 10;
  static const _kStartTimeShiftMs = 50;
  static const _kCarouselOneMs = 100;
  static const _kTotalMs = 1200;

  static const _kEmojiTable = [
    '\u{1F609}', '\u{1F60D}', '\u{1F61B}', '\u{1F62D}', '\u{1F631}', '\u{1F621}',
    '\u{1F60E}', '\u{1F634}', '\u{1F635}', '\u{1F608}', '\u{1F62C}', '\u{1F607}',
    '\u{1F60F}', '\u{1F46E}', '\u{1F477}', '\u{1F482}', '\u{1F476}', '\u{1F468}',
    '\u{1F469}', '\u{1F474}', '\u{1F475}', '\u{1F63B}', '\u{1F63D}', '\u{1F640}',
    '\u{1F47A}', '\u{1F648}', '\u{1F649}', '\u{1F64A}', '\u{1F480}', '\u{1F47D}',
    '\u{1F4A9}', '\u{1F525}', '\u{1F4A5}', '\u{1F4A4}', '\u{1F442}', '\u{1F440}',
    '\u{1F443}', '\u{1F445}', '\u{1F444}', '\u{1F44D}', '\u{1F44E}', '\u{1F44C}',
    '\u{1F44A}', '\u{270C}', '\u{270B}', '\u{1F450}', '\u{1F446}', '\u{1F447}',
    '\u{1F449}', '\u{1F448}', '\u{1F64F}', '\u{1F44F}', '\u{1F4AA}', '\u{1F6B6}',
    '\u{1F3C3}', '\u{1F483}', '\u{1F46B}', '\u{1F46A}', '\u{1F46C}', '\u{1F46D}',
    '\u{1F485}', '\u{1F3A9}', '\u{1F451}', '\u{1F452}', '\u{1F45F}', '\u{1F45E}',
    '\u{1F460}', '\u{1F455}', '\u{1F457}', '\u{1F456}', '\u{1F459}', '\u{1F45C}',
    '\u{1F453}', '\u{1F380}', '\u{1F484}', '\u{1F49B}', '\u{1F499}', '\u{1F49C}',
    '\u{1F49A}', '\u{1F48D}', '\u{1F48E}', '\u{1F436}', '\u{1F43A}', '\u{1F431}',
    '\u{1F42D}', '\u{1F439}', '\u{1F430}', '\u{1F438}', '\u{1F42F}', '\u{1F428}',
    '\u{1F43B}', '\u{1F437}', '\u{1F42E}', '\u{1F417}', '\u{1F434}', '\u{1F411}',
    '\u{1F418}', '\u{1F43C}', '\u{1F427}', '\u{1F425}', '\u{1F414}', '\u{1F40D}',
    '\u{1F422}', '\u{1F41B}', '\u{1F41D}', '\u{1F41C}', '\u{1F41E}', '\u{1F40C}',
    '\u{1F419}', '\u{1F41A}', '\u{1F41F}', '\u{1F42C}', '\u{1F40B}', '\u{1F410}',
    '\u{1F40A}', '\u{1F42B}', '\u{1F340}', '\u{1F339}', '\u{1F33B}', '\u{1F341}',
    '\u{1F33E}', '\u{1F344}', '\u{1F335}', '\u{1F334}', '\u{1F333}', '\u{1F31E}',
    '\u{1F31A}', '\u{1F319}', '\u{1F30E}', '\u{1F30B}', '\u{26A1}', '\u{2614}',
    '\u{2744}', '\u{26C4}', '\u{1F300}', '\u{1F308}', '\u{1F30A}', '\u{1F393}',
    '\u{1F386}', '\u{1F383}', '\u{1F47B}', '\u{1F385}', '\u{1F384}', '\u{1F381}',
    '\u{1F388}', '\u{1F52E}', '\u{1F3A5}', '\u{1F4F7}', '\u{1F4BF}', '\u{1F4BB}',
    '\u{260E}', '\u{1F4E1}', '\u{1F4FA}', '\u{1F4FB}', '\u{1F509}', '\u{1F514}',
    '\u{23F3}', '\u{23F0}', '\u{231A}', '\u{1F512}', '\u{1F511}', '\u{1F50E}',
    '\u{1F4A1}', '\u{1F526}', '\u{1F50C}', '\u{1F50B}', '\u{1F6BF}', '\u{1F6BD}',
    '\u{1F527}', '\u{1F528}', '\u{1F6AA}', '\u{1F6AC}', '\u{1F4A3}', '\u{1F52B}',
    '\u{1F52A}', '\u{1F48A}', '\u{1F489}', '\u{1F4B0}', '\u{1F4B5}', '\u{1F4B3}',
    '\u{2709}', '\u{1F4EB}', '\u{1F4E6}', '\u{1F4C5}', '\u{1F4C1}', '\u{2702}',
    '\u{1F4CC}', '\u{1F4CE}', '\u{2712}', '\u{270F}', '\u{1F4D0}', '\u{1F4DA}',
    '\u{1F52C}', '\u{1F52D}', '\u{1F3A8}', '\u{1F3AC}', '\u{1F3A4}', '\u{1F3A7}',
    '\u{1F3B5}', '\u{1F3B9}', '\u{1F3BB}', '\u{1F3BA}', '\u{1F3B8}', '\u{1F47E}',
    '\u{1F3AE}', '\u{1F0CF}', '\u{1F3B2}', '\u{1F3AF}', '\u{1F3C8}', '\u{1F3C0}',
    '\u{26BD}', '\u{26BE}', '\u{1F3BE}', '\u{1F3B1}', '\u{1F3C9}', '\u{1F3B3}',
    '\u{1F3C1}', '\u{1F3C7}', '\u{1F3C6}', '\u{1F3CA}', '\u{1F3C4}', '\u{2615}',
    '\u{1F37C}', '\u{1F37A}', '\u{1F377}', '\u{1F374}', '\u{1F355}', '\u{1F354}',
    '\u{1F35F}', '\u{1F357}', '\u{1F371}', '\u{1F35A}', '\u{1F35C}', '\u{1F361}',
    '\u{1F373}', '\u{1F35E}', '\u{1F369}', '\u{1F366}', '\u{1F382}', '\u{1F370}',
    '\u{1F36A}', '\u{1F36B}', '\u{1F36D}', '\u{1F36F}', '\u{1F34E}', '\u{1F34F}',
    '\u{1F34A}', '\u{1F34B}', '\u{1F352}', '\u{1F347}', '\u{1F349}', '\u{1F353}',
    '\u{1F351}', '\u{1F34C}', '\u{1F350}', '\u{1F34D}', '\u{1F346}', '\u{1F345}',
    '\u{1F33D}', '\u{1F3E1}', '\u{1F3E5}', '\u{1F3E6}', '\u{26EA}', '\u{1F3F0}',
    '\u{26FA}', '\u{1F3ED}', '\u{1F5FB}', '\u{1F5FD}', '\u{1F3A0}', '\u{1F3A1}',
    '\u{26F2}', '\u{1F3A2}', '\u{1F6A2}', '\u{1F6A4}', '\u{2693}', '\u{1F680}',
    '\u{2708}', '\u{1F681}', '\u{1F682}', '\u{1F68B}', '\u{1F68E}', '\u{1F68C}',
    '\u{1F699}', '\u{1F697}', '\u{1F695}', '\u{1F69B}', '\u{1F6A8}', '\u{1F694}',
    '\u{1F692}', '\u{1F691}', '\u{1F6B2}', '\u{1F6A0}', '\u{1F69C}', '\u{1F6A6}',
    '\u{26A0}', '\u{1F6A7}', '\u{26FD}', '\u{1F3B0}', '\u{1F5FF}', '\u{1F3AA}',
    '\u{1F3AD}',
    '\u{1F1EF}\u{1F1F5}', '\u{1F1F0}\u{1F1F7}', '\u{1F1E9}\u{1F1EA}',
    '\u{1F1E8}\u{1F1F3}', '\u{1F1FA}\u{1F1F8}', '\u{1F1EB}\u{1F1F7}',
    '\u{1F1EA}\u{1F1F8}', '\u{1F1EE}\u{1F1F9}', '\u{1F1F7}\u{1F1FA}',
    '\u{1F1EC}\u{1F1E7}',
    '1\u{20E3}', '2\u{20E3}', '3\u{20E3}', '4\u{20E3}', '5\u{20E3}',
    '6\u{20E3}', '7\u{20E3}', '8\u{20E3}', '9\u{20E3}', '0\u{20E3}',
    '\u{1F51F}', '\u{2757}', '\u{2753}', '\u{2665}', '\u{2666}', '\u{1F4AF}',
    '\u{1F517}', '\u{1F531}', '\u{1F534}', '\u{1F535}', '\u{1F536}', '\u{1F537}',
  ];

  @override
  void initState() {
    super.initState();
    _generateCarouselSequences();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _kTotalMs),
    )..forward();
  }

  @override
  void didUpdateWidget(_EncryptionFingerprint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emoji.join() != widget.emoji.join()) {
      _generateCarouselSequences();
      _controller.forward(from: 0.0);
    }
  }

  void _generateCarouselSequences() {
    final rng = math.Random(widget.emoji.join().hashCode);
    _carouselSequences = List.generate(_kEmojiCount, (i) {
      return List.generate(_kCarouselCount, (_) {
        return _kEmojiTable[rng.nextInt(_kEmojiTable.length)];
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _emojiAt(int pos, double elapsedMs) {
    final startMs = pos * _kStartTimeShiftMs;
    final elapsed = elapsedMs - startMs;
    if (elapsed < 0) return _carouselSequences[pos][0];

    final totalDistance = _kCarouselCount.toDouble();
    final totalTime = _kCarouselCount * _kCarouselOneMs.toDouble();
    final accelPhase = totalTime * 0.25;
    final decelPhase = totalTime * 0.35;
    final constPhase = totalTime - accelPhase - decelPhase;
    final maxSpeed = totalDistance / (accelPhase * 0.5 + constPhase + decelPhase * 0.5);

    double position;
    if (elapsed >= totalTime) {
      return widget.emoji[pos];
    } else if (elapsed < accelPhase) {
      final t = elapsed / accelPhase;
      final speed = maxSpeed * t;
      position = speed * elapsed * 0.5 / totalDistance * _kCarouselCount;
    } else if (elapsed < accelPhase + constPhase) {
      final accelDist = maxSpeed * accelPhase * 0.5;
      final constElapsed = elapsed - accelPhase;
      position = (accelDist + maxSpeed * constElapsed) / totalDistance * _kCarouselCount;
    } else {
      final accelDist = maxSpeed * accelPhase * 0.5;
      final constDist = maxSpeed * constPhase;
      final decelElapsed = elapsed - accelPhase - constPhase;
      final t = decelElapsed / decelPhase;
      final decelDist = maxSpeed * decelElapsed * (1.0 - t * 0.5);
      position = (accelDist + constDist + decelDist) / totalDistance * _kCarouselCount;
    }

    final idx = position.floor().clamp(0, _kCarouselCount - 1);
    return _carouselSequences[pos][idx];
  }

  @override
  Widget build(BuildContext context) {
    return TelegramTooltip(
      // AyuGram `lng_call_fingerprint_tooltip`: actionable verification instruction,
      // formatted with the user's name — not a generic "is encrypted" assertion.
      message: widget.callerName.isNotEmpty
          ? "If the emoji on ${widget.callerName}'s screen are the same, this call is 100% secure"
          : 'If the emoji on both screens are the same, this call is 100% secure',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final elapsedMs = _controller.value * _kTotalMs;
          // No background here — the badge in _buildFingerprintBadge paints the
          // shared callBgButton shape. This renders just the emoji row, spaced
          // by callFingerprintSkip (4px).
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_kEmojiCount, (i) {
              return Padding(
                padding: EdgeInsets.only(left: i > 0 ? 4 : 0),
                child: Text(
                  _emojiAt(i, elapsedMs),
                  style: const TextStyle(
                    fontSize: 18,
                    decoration: TextDecoration.none,
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  final int quality;

  const _SignalBars({required this.quality});

  static const _barCount = 4;
  static const _barWidth = 2.0;
  static const _minHeight = 4.0;
  static const _maxHeight = 10.0;
  static const _skip = 2.0;
  static const _totalWidth = _barCount * _barWidth + (_barCount - 1) * _skip;

  @override
  Widget build(BuildContext context) {
    if (quality < 0) return const SizedBox.shrink();
    return CustomPaint(
      size: const Size(_totalWidth, _maxHeight),
      painter: _SignalBarsPainter(quality: quality),
    );
  }
}

class _SignalBarsPainter extends CustomPainter {
  final int quality;

  _SignalBarsPainter({required this.quality});

  static const _barCount = 4;
  static const _barWidth = 2.0;
  static const _minHeight = 4.0;
  static const _maxHeight = 10.0;
  static const _skip = 2.0;
  static const _radius = Radius.circular(1.0);

  int get _activeBars => quality.clamp(0, _barCount);

  @override
  void paint(Canvas canvas, Size size) {
    final active = _activeBars;

    for (int i = 0; i < _barCount; i++) {
      final barHeight =
          _minHeight + (_maxHeight - _minHeight) * (i / (_barCount - 1));
      final x = i * (_barWidth + _skip);
      final y = size.height - barHeight;

      final paint = Paint()
        ..color = i < active
            ? const Color(0xFFFFFFFF)
            : const Color(0x80FFFFFF)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, _barWidth, barHeight),
          _radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SignalBarsPainter old) => old.quality != quality;
}

enum _SnapCorner { topLeft, topRight, bottomLeft, bottomRight }

class _SelfViewBubble extends StatefulWidget {
  final Widget videoWidget;
  final bool mirror;

  const _SelfViewBubble({required this.videoWidget, this.mirror = true});

  static const _width = 160.0;
  static const _height = 110.0;
  static const _inset = 12.0;
  static const _snapDuration = Duration(milliseconds: 120);
  static const _borderRadius = 8.0;

  @override
  State<_SelfViewBubble> createState() => _SelfViewBubbleState();
}

class _SelfViewBubbleState extends State<_SelfViewBubble>
    with SingleTickerProviderStateMixin {
  _SnapCorner _corner = _SnapCorner.bottomRight;
  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;
  late AnimationController _snapController;
  Offset _snapFrom = Offset.zero;
  Offset _snapTo = Offset.zero;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: _SelfViewBubble._snapDuration,
    );
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  Offset _cornerPosition(Size parentSize, _SnapCorner corner) {
    const i = _SelfViewBubble._inset;
    const w = _SelfViewBubble._width;
    const h = _SelfViewBubble._height;
    switch (corner) {
      case _SnapCorner.topLeft:
        return const Offset(i, i);
      case _SnapCorner.topRight:
        return Offset(parentSize.width - w - i, i);
      case _SnapCorner.bottomLeft:
        return Offset(i, parentSize.height - h - i);
      case _SnapCorner.bottomRight:
        return Offset(parentSize.width - w - i, parentSize.height - h - i);
    }
  }

  _SnapCorner _nearestCorner(Offset center, Size parentSize) {
    _SnapCorner best = _SnapCorner.bottomRight;
    double bestDist = double.infinity;
    for (final c in _SnapCorner.values) {
      final pos = _cornerPosition(parentSize, c);
      final cornerCenter = Offset(
        pos.dx + _SelfViewBubble._width / 2,
        pos.dy + _SelfViewBubble._height / 2,
      );
      final dist = (cornerCenter - center).distance;
      if (dist < bestDist) {
        bestDist = dist;
        best = c;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    Widget videoContent = ClipRRect(
      borderRadius: BorderRadius.circular(_SelfViewBubble._borderRadius),
      child: SizedBox(
        width: _SelfViewBubble._width,
        height: _SelfViewBubble._height,
        child: widget.videoWidget,
      ),
    );

    if (widget.mirror) {
      videoContent = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scale(-1.0, 1.0),
        child: videoContent,
      );
    }

    final stableChild = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_SelfViewBubble._borderRadius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: videoContent,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final parentSize = Size(constraints.maxWidth, constraints.maxHeight);

        return AnimatedBuilder(
          animation: _snapController,
          builder: (context, child) {
            Offset currentPos;
            if (_isDragging) {
              currentPos = _dragOffset;
            } else if (_snapController.isAnimating) {
              final t = Curves.easeOutCirc.transform(_snapController.value);
              currentPos = Offset.lerp(_snapFrom, _snapTo, t)!;
            } else {
              currentPos = _cornerPosition(parentSize, _corner);
            }

            return Positioned(
              left: currentPos.dx,
              top: currentPos.dy,
              child: GestureDetector(
                onPanStart: (details) {
                  _snapController.stop();
                  setState(() {
                    _isDragging = true;
                    _dragOffset = currentPos;
                  });
                },
                onPanUpdate: (details) {
                  setState(() {
                    _dragOffset += details.delta;
                    _dragOffset = Offset(
                      _dragOffset.dx.clamp(0, parentSize.width - _SelfViewBubble._width),
                      _dragOffset.dy.clamp(0, parentSize.height - _SelfViewBubble._height),
                    );
                  });
                },
                onPanEnd: (_) {
                  final center = Offset(
                    _dragOffset.dx + _SelfViewBubble._width / 2,
                    _dragOffset.dy + _SelfViewBubble._height / 2,
                  );
                  final newCorner = _nearestCorner(center, parentSize);
                  _snapFrom = _dragOffset;
                  _snapTo = _cornerPosition(parentSize, newCorner);
                  setState(() {
                    _isDragging = false;
                    _corner = newCorner;
                  });
                  _snapController.forward(from: 0.0);
                },
                child: child!,
              ),
            );
          },
          child: stableChild,
        );
      },
    );
  }
}

class _OutgoingPreview extends StatelessWidget {
  final Widget videoWidget;
  final double containerHeight;
  final double innerWidth;

  const _OutgoingPreview({
    required this.videoWidget,
    required this.containerHeight,
    required this.innerWidth,
  });

  // AyuGram calls.style:70-72.
  static const _previewMin = Size(360, 120);      // callOutgoingPreviewMin
  static const _previewDefault = Size(540, 180);  // callOutgoingPreview (at height == callHeight)
  static const _previewMax = Size(1620, 540);     // callOutgoingPreviewMax (clamp ceiling only)

  @override
  Widget build(BuildContext context) {
    // AyuGram calls_panel.cpp:1198-1209: interpolate Min→Default by
    // (innerHeight - callHeightMin) / (callHeight - callHeightMin), anchored at
    // callHeightMin (520) — NOT ramping toward the Max size — then clamp width
    // to min(innerWidth, Max.w) and height to Max.h. At the panel's clamped
    // 520–540px height this yields ≈360×120 → 540×180, a small in-body block,
    // not the ≈1440–1620px fullscreen self-camera the old anchor produced.
    const heightMin = CallPanel.minHeight;          // callHeightMin = 520
    const heightDefault = CallPanel.defaultHeight;  // callHeight = 540
    final innerHeight = math.max(containerHeight, heightMin);
    final ratio = (innerHeight - heightMin) / (heightDefault - heightMin);
    final maxW = _previewMin.width +
        (_previewDefault.width - _previewMin.width) * ratio;
    final maxH = _previewMin.height +
        (_previewDefault.height - _previewMin.height) * ratio;
    final w = math.min(maxW, math.min(innerWidth, _previewMax.width));
    final h = math.min(maxH, _previewMax.height);

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..scale(-1.0, 1.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: w,
          height: h,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: w,
              height: h,
              child: videoWidget,
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders the remote peer's live 1:1 call video. Polls the engine for the
/// latest decoded incoming frame (the same getter group-call tiles use — the Go
/// side resolves 1:1 calls too) and paints it cover-fit, mirroring AyuGram
/// binding the panel to `_call->videoIncoming()`. The panel only mounts this
/// while the remote video track is active, so a real video call — or the peer
/// turning on their camera mid-call — now displays instead of just the avatar.
/// Until the first frame arrives it shows the dark call background (the userpic
/// + name overlay painted by the panel sits on top), the same no-frame state the
/// group-call tiles use.
class _CallVideoView extends StatefulWidget {
  final String callId;
  final String kind; // "camera" or "screen"

  const _CallVideoView({super.key, required this.callId, this.kind = 'camera'});

  @override
  State<_CallVideoView> createState() => _CallVideoViewState();
}

class _CallVideoViewState extends State<_CallVideoView> {
  Timer? _timer;
  ui.Image? _frame;
  bool _decoding = false;

  @override
  void initState() {
    super.initState();
    // ~12fps poll — enough for a smooth surface without flooding the FFI bridge
    // (matches the group-call tile cadence).
    _timer = Timer.periodic(const Duration(milliseconds: 80), (_) => _poll());
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _frame?.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    if (!mounted || _decoding || widget.callId.isEmpty) return;
    try {
      final engine = context.read<EngineService>();
      final accountId = context.read<AppState>().activeAccountId;
      final f = await engine.getGroupCallVideoFrame(accountId, widget.callId, widget.kind);
      if (!mounted) return;
      if (f == null) {
        if (_frame != null) {
          final old = _frame;
          setState(() => _frame = null);
          old?.dispose();
        }
        return;
      }
      _decoding = true;
      ui.decodeImageFromPixels(
          f.rgba, f.width, f.height, ui.PixelFormat.rgba8888, (img) {
        _decoding = false;
        if (!mounted) {
          img.dispose();
          return;
        }
        final old = _frame;
        setState(() => _frame = img);
        old?.dispose();
      });
    } catch (e) {
      _decoding = false;
      Debug.log('call_panel', '_CallVideoView poll: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    return ColoredBox(
      color: const Color(0xFF15202B),
      child: frame == null
          ? const SizedBox.expand()
          : RawImage(
              image: frame,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
    );
  }
}

/// Maps an engine call-state string to a [CallPanelState]. Mirrors the parser
/// used for incoming calls (main.dart) so outgoing calls report the same
/// requesting → ringing → exchanging-keys → active → ended progression.
CallPanelState parseCallPanelState(String state) => switch (state) {
  'connecting' => CallPanelState.connecting,
  'exchangingKeys' || 'exchanging_keys' => CallPanelState.exchangingKeys,
  'waiting' => CallPanelState.waiting,
  'requesting' => CallPanelState.requesting,
  'ringing' => CallPanelState.ringing,
  'hangingUp' || 'hanging_up' => CallPanelState.hangingUp,
  'active' => CallPanelState.active,
  'ended' => CallPanelState.ended,
  'failed' => CallPanelState.failed,
  'busy' => CallPanelState.busy,
  'waitingUserConfirmation' || 'waiting_user_confirmation' =>
    CallPanelState.waitingUserConfirmation,
  _ => CallPanelState.incoming,
};

/// Resolves the engine's `meta['fingerprint']` (the four ComputeEmojiIndex
/// values of SHA256(authKey ++ g_a), comma-joined) into the four verification
/// emoji. Each value is taken modulo the canonical 333-emoji table, exactly like
/// AyuGram `ComputeEmojiFingerprint` (calls_emoji_fingerprint.cpp:156-168 →
/// `value % kEmojiCount`). Returns `const []` until the key — and therefore the
/// fingerprint — is ready, so the badge only appears for a real, keyed call.
List<String> callFingerprintEmojiFromMeta(Map<String, String> meta) {
  final raw = meta['fingerprint'];
  if (raw == null || raw.isEmpty) return const [];
  final parts = raw.split(',');
  if (parts.length != 4) return const [];
  const table = _EncryptionFingerprintState._kEmojiTable;
  final out = <String>[];
  for (final p in parts) {
    final v = int.tryParse(p.trim());
    if (v == null) return const [];
    out.add(table[(v % table.length).abs()]);
  }
  return out;
}

/// Resolves the engine's `meta['signal_bars']` (0..4 once connected) into the
/// panel's `signalQuality`. Defaults to -1 (bars hidden) until the engine
/// reports connectivity — mirrors AyuGram binding to `signalBarCountValue()`.
int callSignalQualityFromMeta(Map<String, String> meta) =>
    int.tryParse(meta['signal_bars'] ?? '') ?? -1;

/// Resolves the engine's authoritative connect time (`meta['connect_time_ms']`,
/// stamped when the call instance first reaches active) so the duration clock
/// counts from the true connect moment — AyuGram displays `getDurationMs()`,
/// not the moment the client first observed the active state.
DateTime? callConnectTimeFromMeta(Map<String, String> meta) {
  final ms = int.tryParse(meta['connect_time_ms'] ?? '');
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}

/// Places a real outgoing 1:1 call and shows the live call panel bound to it.
///
/// Mirrors AyuGram `Instance::startOutgoingCall` (calls_instance.cpp:199): it
/// creates a real Call via the engine (`engine.startCall`) and binds the panel
/// to its live state stream (`engine.onCallState`), so the hangup control
/// operates on the real call and the panel advances through requesting →
/// ringing → exchanging-keys → active instead of being frozen on "connecting…"
/// forever. This is the single entry point the DM call buttons use.
void startOutgoingCall(
  BuildContext context, {
  required String chatId,
  required String chatTitle,
  required String avatarPath,
  required bool isVideo,
}) {
  final engine = context.read<EngineService>();
  final accountId = context.read<AppState>().activeAccountId;

  final infoController = StreamController<CallPanelInfo>.broadcast();
  var liveCallId = '';
  var conferenceSupported = false;
  StreamSubscription<CallStateEvent>? sub;

  void teardown() {
    sub?.cancel();
    sub = null;
    if (!infoController.isClosed) infoController.close();
  }

  CallPanelInfo build(CallPanelState state, {String callId = ''}) => CallPanelInfo(
        callerId: chatId,
        callerName: chatTitle,
        callerAvatarUrl: avatarPath,
        isVideo: isVideo,
        state: state,
        callId: callId,
        conferenceSupported: conferenceSupported,
      );

  sub = engine.onCallState.listen((event) {
    final call = event.call;
    // Bind to the call that belongs to this chat. Its id isn't known until the
    // engine returns it (StartCall) or emits the first state event, so match by
    // chat id first, then stick to the resolved call id.
    final matches = (liveCallId.isNotEmpty && call.id == liveCallId) ||
        (liveCallId.isEmpty && call.chatId == chatId);
    if (!matches) return;
    if (call.id.isNotEmpty) liveCallId = call.id;

    final meta = call.meta;
    if (meta['conference_supported'] == 'true') conferenceSupported = true;
    final newState = parseCallPanelState(call.state);
    infoController.add(CallPanelInfo(
      callerId: chatId,
      callerName: chatTitle,
      callerAvatarUrl: avatarPath,
      isVideo: isVideo || call.isVideo,
      state: newState,
      callId: call.id,
      conferenceSupported: conferenceSupported,
      isRemoteMuted: meta['remote_muted'] == 'true',
      isRemoteLowBattery: meta['remote_low_battery'] == 'true',
      // Live status from the engine — the same data AyuGram's Panel binds to.
      fingerprintEmoji: callFingerprintEmojiFromMeta(meta),
      signalQuality: callSignalQualityFromMeta(meta),
      callStartTime: callConnectTimeFromMeta(meta),
      isRemoteVideoActive: meta['remote_video_state'] == 'active',
      // Local media state, sourced from the engine (AyuGram binds the mute /
      // camera / screencast buttons to mutedValue() / isSharingCamera() /
      // isSharingScreen()) so the screencast "Stop" state and the optimistic
      // mute/camera toggles reflect engine truth, not client-side guesses.
      isMuted: meta['is_muted'] == 'true',
      isCameraOn: meta['is_camera_on'] == 'true',
      isScreenSharing: meta['is_screen_sharing'] == 'true',
    ));
    if (newState == CallPanelState.ended ||
        newState == CallPanelState.failed ||
        newState == CallPanelState.busy) {
      teardown();
    }
  });

  // Show the panel immediately, bound to the live stream (AyuGram opens the
  // panel as soon as the Call is created). _LiveCallPanelDialog derives its
  // effective call id from the streamed CallPanelInfo, so the controls become
  // functional the moment the engine reports the call id.
  showCallPanel(
    context,
    build(CallPanelState.requesting),
    infoStream: infoController.stream,
  );

  // Actually place the call (AyuGram: createCall(user, Type::Outgoing, args)).
  engine.startCall(accountId, chatId, video: isVideo).then((callId) {
    if (callId != null && callId.isNotEmpty) {
      liveCallId = callId;
      // Seed the panel with the resolved id immediately so the hangup control
      // works even before the first onCallState event arrives.
      if (!infoController.isClosed) {
        infoController.add(build(CallPanelState.requesting, callId: callId));
      }
    } else if (!infoController.isClosed) {
      // Initiation failed outright — surface a "failed" panel and tear down.
      infoController.add(build(CallPanelState.failed));
      teardown();
    }
  });
}

/// Shows the incoming 1:1 call panel for a real incoming call and binds it to
/// the live call state (`engine.onCallState`). Mirrors AyuGram opening the panel
/// from `createCall(user, Call::Type::Incoming, …)` in `handleCallUpdate`
/// (calls_instance.cpp:707). Before this, the panel's incoming state — and so
/// the Answer button — only ever rendered from the debug command; a real
/// incoming call never displayed it. The panel's onAccept/onDecline drive
/// `engine.acceptCall` / `engine.declineCall` on the real call.
void startIncomingCall(
  BuildContext context, {
  required String callId,
  required String callerId,
  required String callerName,
  required String avatarPath,
  required bool isVideo,
}) {
  final engine = context.read<EngineService>();

  final infoController = StreamController<CallPanelInfo>.broadcast();
  var conferenceSupported = false;
  StreamSubscription<CallStateEvent>? sub;

  void teardown() {
    sub?.cancel();
    sub = null;
    if (!infoController.isClosed) infoController.close();
  }

  sub = engine.onCallState.listen((event) {
    final call = event.call;
    if (call.id != callId) return;
    final meta = call.meta;
    if (meta['conference_supported'] == 'true') conferenceSupported = true;
    var newState = parseCallPanelState(call.state);
    // While still ringing (not yet accepted), keep showing the incoming state
    // (Answer/Decline) rather than the outgoing "ringing…" view. Once we accept,
    // the engine advances past ringing (connecting → active) on its own.
    if (newState == CallPanelState.ringing) {
      newState = CallPanelState.incoming;
    }
    infoController.add(CallPanelInfo(
      callerId: callerId,
      callerName: callerName,
      callerAvatarUrl: avatarPath,
      isVideo: isVideo || call.isVideo,
      state: newState,
      callId: call.id,
      conferenceSupported: conferenceSupported,
      isRemoteMuted: meta['remote_muted'] == 'true',
      isRemoteLowBattery: meta['remote_low_battery'] == 'true',
      fingerprintEmoji: callFingerprintEmojiFromMeta(meta),
      signalQuality: callSignalQualityFromMeta(meta),
      callStartTime: callConnectTimeFromMeta(meta),
      isRemoteVideoActive: meta['remote_video_state'] == 'active',
      // Local media state from the engine (see startOutgoingCall).
      isMuted: meta['is_muted'] == 'true',
      isCameraOn: meta['is_camera_on'] == 'true',
      isScreenSharing: meta['is_screen_sharing'] == 'true',
    ));
    if (newState == CallPanelState.ended ||
        newState == CallPanelState.failed ||
        newState == CallPanelState.busy) {
      teardown();
    }
  });

  showCallPanel(
    context,
    CallPanelInfo(
      callerId: callerId,
      callerName: callerName,
      callerAvatarUrl: avatarPath,
      isVideo: isVideo,
      state: CallPanelState.incoming,
      callId: callId,
    ),
    callId: callId,
    infoStream: infoController.stream,
  );
}

void showCallPanel(
  BuildContext context,
  CallPanelInfo info, {
  String? callId,
  Widget? remoteVideoWidget,
  Widget? selfVideoWidget,
  Stream<CallPanelInfo>? infoStream,
}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (ctx) {
      final effectiveCallId = callId ?? info.callId;
      return _LiveCallPanelDialog(
        initialInfo: info,
        infoStream: infoStream,
        effectiveCallId: effectiveCallId,
        remoteVideoWidget: remoteVideoWidget,
        selfVideoWidget: selfVideoWidget,
      );
    },
  );
}

class _LiveCallPanelDialog extends StatefulWidget {
  final CallPanelInfo initialInfo;
  final Stream<CallPanelInfo>? infoStream;
  final String effectiveCallId;
  final Widget? remoteVideoWidget;
  final Widget? selfVideoWidget;

  const _LiveCallPanelDialog({
    required this.initialInfo,
    this.infoStream,
    required this.effectiveCallId,
    this.remoteVideoWidget,
    this.selfVideoWidget,
  });

  @override
  State<_LiveCallPanelDialog> createState() => _LiveCallPanelDialogState();
}

class _LiveCallPanelDialogState extends State<_LiveCallPanelDialog> {
  late CallPanelInfo _currentInfo;
  StreamSubscription<CallPanelInfo>? _sub;

  // The call's id may not be known when the panel opens for an OUTGOING call:
  // StartCall returns it asynchronously and the engine streams it via
  // onCallState. Prefer the explicit id, then fall back to the live id carried
  // by the latest CallPanelInfo, so the accept/decline/hangup controls operate
  // on the real call instead of being permanent no-ops.
  String get _liveCallId => widget.effectiveCallId.isNotEmpty
      ? widget.effectiveCallId
      : _currentInfo.callId;

  // The video tracks aren't known when the panel opens for a real call, so the
  // remote-video surface is built from the LIVE call state rather than passed
  // once at construction — AyuGram switches to the video layout when
  // `_call->videoIncoming()` activates. An explicitly-supplied widget (the
  // flutter_interact debug command) still takes precedence.
  Widget? get _remoteVideo {
    if (widget.remoteVideoWidget != null) return widget.remoteVideoWidget;
    if (_currentInfo.state == CallPanelState.active &&
        _currentInfo.isRemoteVideoActive &&
        _liveCallId.isNotEmpty) {
      return _CallVideoView(
        key: ValueKey('remote_video_$_liveCallId'),
        callId: _liveCallId,
      );
    }
    return null;
  }

  // Local self-preview, built from the LIVE call state exactly like _remoteVideo:
  // AyuGram always creates _outgoingVideoBubble from _call->videoOutgoing() and
  // shows it whenever the camera or screen is being captured. The engine caches
  // the locally-sent frames (outgoing_camera / outgoing_screen endpoints), so the
  // preview renders real frames when a capture source feeds them. An explicitly
  // supplied widget (the flutter_interact debug command) still takes precedence.
  Widget? get _selfVideo {
    if (widget.selfVideoWidget != null) return widget.selfVideoWidget;
    if (_liveCallId.isEmpty) return null;
    // Screen share takes visual priority over the camera (AyuGram mirrors the
    // bubble for the camera but not for a screen-share).
    if (_currentInfo.isScreenSharing) {
      return _CallVideoView(
        key: ValueKey('self_screen_$_liveCallId'),
        callId: _liveCallId,
        kind: 'outgoing_screen',
      );
    }
    if (_currentInfo.isCameraOn) {
      return _CallVideoView(
        key: ValueKey('self_camera_$_liveCallId'),
        callId: _liveCallId,
        kind: 'outgoing_camera',
      );
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _currentInfo = widget.initialInfo;
    _sub = widget.infoStream?.listen((info) {
      if (mounted) setState(() => _currentInfo = info);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _closeAndRate() {
    Navigator.of(context).pop();
    if (_liveCallId.isNotEmpty && _currentInfo.needRating) {
      showCallRatingDialog(context, callId: _liveCallId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width.clamp(CallPanel.minWidth, CallPanel.defaultWidth);
    final dialogHeight = screenSize.height.clamp(CallPanel.minHeight, CallPanel.defaultHeight);
    return Center(
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CallPanel(
            info: _currentInfo,
            onClose: _closeAndRate,
            onDecline: () {
              final callId = _liveCallId;
              if (callId.isNotEmpty) {
                final engine = context.read<EngineService>();
                final accountId = context.read<AppState>().activeAccountId;
                engine.declineCall(accountId, callId);
              }
              Navigator.of(context).pop();
            },
            onAccept: () {
              final callId = _liveCallId;
              if (callId.isNotEmpty) {
                final engine = context.read<EngineService>();
                final accountId = context.read<AppState>().activeAccountId;
                engine.acceptCall(accountId, callId);
              }
            },
            onHangup: () {
              final callId = _liveCallId;
              if (callId.isNotEmpty) {
                final engine = context.read<EngineService>();
                final accountId = context.read<AppState>().activeAccountId;
                engine.endCall(accountId, callId);
              }
              _closeAndRate();
            },
            onRedial: () {
              final engine = context.read<EngineService>();
              final accountId = context.read<AppState>().activeAccountId;
              final chatId = _currentInfo.callerId;
              if (chatId.isNotEmpty) {
                engine.startCall(accountId, chatId, video: _currentInfo.isVideo);
              }
            },
            onStartCall: (video) {
              final engine = context.read<EngineService>();
              final accountId = context.read<AppState>().activeAccountId;
              final chatId = _currentInfo.callerId;
              if (chatId.isNotEmpty) {
                engine.startCall(accountId, chatId, video: video);
              }
            },
            remoteVideoWidget: _remoteVideo,
            // Self-view (outgoing camera / screen) derived from the live call
            // state, mirroring AyuGram's always-present _outgoingVideoBubble bound
            // to _call->videoOutgoing(). It polls the engine's outgoing-frame
            // endpoint and renders frames when a capture source feeds them.
            selfVideoWidget: _selfVideo,
          ),
        ),
      ),
    );
  }
}

void showCallRatingDialog(BuildContext context, {required String callId}) {
  showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black54,
    builder: (ctx) => CallRatingDialog(callId: callId),
  );
}

class CallRatingDialog extends StatefulWidget {
  final String callId;
  const CallRatingDialog({super.key, required this.callId});

  @override
  State<CallRatingDialog> createState() => _CallRatingDialogState();
}

class _CallRatingDialogState extends State<CallRatingDialog> {
  int _selectedRating = 0;
  final _commentController = TextEditingController();
  final _commentFocusNode = FocusNode();
  bool _submitting = false;

  static const _kCommentMaxLength = 200;

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedRating == 0 || _submitting) return;
    setState(() => _submitting = true);
    try {
      final engine = context.read<EngineService>();
      final accountId = context.read<AppState>().activeAccountId;
      final comment = _selectedRating < 5 ? _commentController.text.trim() : '';
      await engine.sendCallRating(
        accountId,
        widget.callId,
        _selectedRating,
        comment,
      );
    } catch (e) {
      Debug.log('call_panel', 'final engine = context.read<EngineService>(): $e');
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _setRating(int rating) {
    setState(() {
      _selectedRating = rating;
      if (rating > 0 && rating < 5) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _commentFocusNode.requestFocus();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final windowSubTextFg = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final starSelectedColor = context.palette.lightButtonFg;
    final accentColor = context.palette.windowBgActive;
    final borderColor = isDark ? const Color(0xFF2b3640) : const Color(0xFFD8D8DD);

    final showComment = _selectedRating > 0 && _selectedRating < 5;

    return AlertDialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: EdgeInsets.zero,
      actionsPadding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
      title: Text(
        'Please rate the quality of your call',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
      content: SizedBox(
        width: 364,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 12, right: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final starIndex = i + 1;
                  final isSelected = starIndex <= _selectedRating;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: InkResponse(
                        onTap: () => _setRating(starIndex),
                        radius: 18,
                        child: Icon(
                          isSelected ? Icons.star_rounded : Icons.star_outline_rounded,
                          size: 36,
                          color: isSelected ? starSelectedColor : windowSubTextFg,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            if (showComment) ...[
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 8, right: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 135),
                  child: TextField(
                    controller: _commentController,
                    focusNode: _commentFocusNode,
                    maxLines: null,
                    maxLength: _kCommentMaxLength,
                    style: TextStyle(
                      fontSize: 14,
                      color: textColor,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Comment (optional)',
                      hintStyle: TextStyle(fontSize: 14, color: windowSubTextFg),
                      counterText: '',
                      contentPadding: const EdgeInsets.fromLTRB(1, 26, 1, 4),
                      border: UnderlineInputBorder(
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: accentColor),
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(color: accentColor),
          ),
        ),
        if (_selectedRating > 0)
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accentColor,
                    ),
                  )
                : Text(
                    'Send',
                    style: TextStyle(color: accentColor),
                  ),
          ),
      ],
    );
  }
}
