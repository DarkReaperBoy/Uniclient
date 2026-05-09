import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/telegram_palette.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../state/app_state.dart';
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
  };
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
  final int signalQuality;
  final List<String> fingerprintEmoji;
  final String callId;
  final DateTime? callStartTime;

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
    this.signalQuality = -1,
    this.fingerprintEmoji = const [],
    this.callId = '',
    this.callStartTime,
  });
}

class CallPanel extends StatefulWidget {
  final CallPanelInfo info;
  final VoidCallback? onDecline;
  final VoidCallback? onAccept;
  final VoidCallback? onHangup;
  final VoidCallback? onClose;
  final Widget? remoteVideoWidget;
  final Widget? selfVideoWidget;

  const CallPanel({
    super.key,
    required this.info,
    this.onDecline,
    this.onAccept,
    this.onHangup,
    this.onClose,
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
  List<Color>? _dominantColors;
  late AnimationController _rippleController;
  late AnimationController _controlsFadeController;
  Timer? _durationTimer;
  Timer? _controlsHideTimer;
  int _durationSeconds = 0;
  bool _controlsVisible = true;
  bool _isMuted = false;
  bool _isCameraOn = false;
  String _selectedCameraDevice = 'Default Camera';
  String _selectedMicDevice = 'Default Microphone';

  static const _kHideControlsFullscreen = Duration(milliseconds: 5000);
  static const _kHideControlsMouseLeave = Duration(milliseconds: 2000);

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _controlsFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      value: 1.0,
    );
    _extractDominantColors();
    if (widget.info.state == CallPanelState.active) {
      _startDurationTimer();
      if (widget.info.isFullscreen) {
        _scheduleControlsHide(_kHideControlsFullscreen);
      }
    }
  }

  @override
  void didUpdateWidget(CallPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.info.callerAvatarUrl != widget.info.callerAvatarUrl ||
        oldWidget.info.callerId != widget.info.callerId) {
      _extractDominantColors();
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

  @override
  void dispose() {
    _rippleController.dispose();
    _controlsFadeController.dispose();
    _durationTimer?.cancel();
    _controlsHideTimer?.cancel();
    super.dispose();
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
    if (widget.info.isFullscreen) {
      _scheduleControlsHide(_kHideControlsFullscreen);
    }
  }

  void _startDurationTimer() {
    final startTime = widget.info.callStartTime ?? DateTime.now();
    _durationSeconds = DateTime.now().difference(startTime).inSeconds;
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _durationSeconds = DateTime.now().difference(startTime).inSeconds;
        });
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
      await engine.endCall(accountId, callId);
      return;
    }
    final result = await showScreenShareChooser(context);
    if (result != null && mounted) {
      await engine.startCall(accountId, widget.info.callerId, video: true);
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
    final result = await engine.createConferenceCall(accountId);
    if (result != null && mounted) {
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

  Future<void> _showDeviceSelectorMenu(BuildContext btnContext) async {
    final RenderBox box = btnContext.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset(box.size.width / 2, 0));
    final result = await showMenu<String>(
      context: btnContext,
      position: RelativeRect.fromLTRB(offset.dx - 100, offset.dy - 8, offset.dx + 100, offset.dy),
      items: [
        const PopupMenuItem(enabled: false, child: Text('Camera', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        PopupMenuItem(value: 'cam_default', child: Text(_selectedCameraDevice, style: const TextStyle(fontSize: 13))),
        const PopupMenuDivider(),
        const PopupMenuItem(enabled: false, child: Text('Microphone', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        PopupMenuItem(value: 'mic_default', child: Text(_selectedMicDevice, style: const TextStyle(fontSize: 13))),
      ],
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.startsWith('cam_')) {
        _selectedCameraDevice = 'Default Camera';
      } else if (result.startsWith('mic_')) {
        _selectedMicDevice = 'Default Microphone';
      }
    });
  }

  void _extractDominantColors() {
    final url = widget.info.callerAvatarUrl;
    if (url.isNotEmpty) {
      _loadImageColors(url);
    } else {
      _setFallbackColors();
    }
  }

  void _setFallbackColors() {
    final id = widget.info.callerId;
    final hash = id.hashCode.abs();
    final hue = (hash % 360).toDouble();
    setState(() {
      _dominantColors = [
        HSLColor.fromAHSL(1.0, hue, 0.5, 0.25).toColor(),
        HSLColor.fromAHSL(1.0, (hue + 40) % 360, 0.6, 0.15).toColor(),
      ];
    });
  }

  Future<void> _loadImageColors(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        _setFallbackColors();
        return;
      }
      final provider = FileImage(file);
      final completer = Completer<ui.Image>();
      final stream = provider.resolve(ImageConfiguration.empty);
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          completer.complete(info.image);
          stream.removeListener(listener);
        },
        onError: (error, _) {
          if (!completer.isCompleted) completer.completeError(error);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);

      final image = await completer.future;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null || !mounted) {
        _setFallbackColors();
        return;
      }

      final pixels = byteData.buffer.asUint8List();
      int totalR = 0, totalG = 0, totalB = 0;
      int darkR = 0, darkG = 0, darkB = 0;
      int darkCount = 0;
      final pixelCount = pixels.length ~/ 4;
      final step = math.max(1, pixelCount ~/ 200);

      for (int i = 0; i < pixels.length; i += step * 4) {
        final r = pixels[i];
        final g = pixels[i + 1];
        final b = pixels[i + 2];
        totalR += r;
        totalG += g;
        totalB += b;
        final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
        if (luminance < 128) {
          darkR += r;
          darkG += g;
          darkB += b;
          darkCount++;
        }
      }

      final samples = pixelCount ~/ step;
      if (samples == 0) {
        _setFallbackColors();
        return;
      }

      final avgColor = Color.fromARGB(
        255,
        (totalR ~/ samples).clamp(0, 255),
        (totalG ~/ samples).clamp(0, 255),
        (totalB ~/ samples).clamp(0, 255),
      );

      Color darkColor;
      if (darkCount > 0) {
        darkColor = Color.fromARGB(
          255,
          (darkR ~/ darkCount).clamp(0, 255),
          (darkG ~/ darkCount).clamp(0, 255),
          (darkB ~/ darkCount).clamp(0, 255),
        );
      } else {
        final hsl = HSLColor.fromColor(avgColor);
        darkColor = hsl.withLightness((hsl.lightness * 0.4).clamp(0.0, 1.0)).toColor();
      }

      if (mounted) {
        setState(() {
          _dominantColors = [
            _darkenColor(avgColor, 0.6),
            _darkenColor(darkColor, 0.7),
          ];
        });
      }
    } catch (_) {
      _setFallbackColors();
    }
  }

  static Color _darkenColor(Color c, double factor) {
    return Color.fromARGB(
      c.alpha,
      (c.red * factor).round().clamp(0, 255),
      (c.green * factor).round().clamp(0, 255),
      (c.blue * factor).round().clamp(0, 255),
    );
  }

  Widget _buildUserpic(double size) {
    final url = widget.info.callerAvatarUrl;
    if (url.isNotEmpty) {
      final file = File(url);
      if (file.existsSync()) {
        return ClipOval(
          child: Image.file(file, width: size, height: size, fit: BoxFit.cover),
        );
      }
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
        Text(
          callPanelStateLabel(widget.info.state, isVideo: widget.info.isVideo),
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
              icon: Icons.call_end,
              label: 'Decline',
              backgroundColor: const Color(0xFFE53935),
              onTap: widget.onDecline,
            ),
            const SizedBox(width: 80),
            _AnswerButton(
              rippleController: _rippleController,
              onTap: widget.onAccept,
              isVideo: widget.info.isVideo,
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
        return Stack(
          children: [
            if (hasPreview)
              Positioned.fill(
                child: _OutgoingPreview(
                  videoWidget: widget.selfVideoWidget!,
                  containerHeight: constraints.maxHeight,
                ),
              ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 3),
                if (!hasPreview) _buildUserpic(160),
                if (!hasPreview) const SizedBox(height: 20),
                Text(
                  widget.info.callerName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    shadows: hasPreview
                        ? const [Shadow(blurRadius: 8, color: Color(0x80000000))]
                        : null,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  callPanelStateLabel(widget.info.state, isVideo: widget.info.isVideo),
                  style: TextStyle(
                    color: const Color(0xAAFFFFFF),
                    fontSize: 15,
                    shadows: hasPreview
                        ? const [Shadow(blurRadius: 8, color: Color(0x80000000))]
                        : null,
                  ),
                ),
                const Spacer(flex: 4),
                _CallActionButton(
                  icon: Icons.call_end,
                  label: 'End Call',
                  backgroundColor: const Color(0xFFE53935),
                  onTap: widget.onHangup,
                  size: 64,
                  iconSize: 32,
                ),
                const SizedBox(height: 48),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildRemotePills() {
    final pills = <Widget>[];
    if (widget.info.isRemoteMuted) {
      pills.add(_RemoteStatusPill(
        icon: Icons.mic_off,
        text: '${widget.info.callerName} muted their microphone',
      ));
    }
    if (widget.info.isRemoteLowBattery) {
      pills.add(_RemoteStatusPill(
        icon: Icons.battery_alert,
        text: '${widget.info.callerName} has low battery',
      ));
    }
    if (pills.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: pills,
      ),
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
          onDeviceChevronTap: _showDeviceSelectorMenu,
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
        ),
        _CallControlButton(
          icon: Icons.person_add_outlined,
          label: 'Add People',
          onTap: _onAddPeopleTap,
        ),
      ],
    );
  }

  Widget _buildStatusRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatDuration(_durationSeconds),
          style: const TextStyle(
            color: Color(0xAAFFFFFF),
            fontSize: 15,
          ),
        ),
        if (widget.info.fingerprintEmoji.length == 4) ...[
          const SizedBox(width: 8),
          _EncryptionFingerprint(emoji: widget.info.fingerprintEmoji),
        ],
        if (widget.info.signalQuality >= 0) ...[
          const SizedBox(width: 8),
          _SignalBars(quality: widget.info.signalQuality),
        ],
      ],
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
    final colors = _dominantColors ?? [const Color(0xFF1a1a2e), const Color(0xFF0f0f1a)];

    Widget content;
    switch (widget.info.state) {
      case CallPanelState.incoming:
        content = _buildIncomingState();
      case CallPanelState.connecting:
      case CallPanelState.exchangingKeys:
      case CallPanelState.waiting:
      case CallPanelState.requesting:
      case CallPanelState.ringing:
        content = _buildConnectingState();
      case CallPanelState.active:
        content = _buildActiveState();
      case CallPanelState.ended:
      case CallPanelState.failed:
      case CallPanelState.busy:
      case CallPanelState.hangingUp:
        content = _buildEndedState();
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: CallPanel.minWidth,
        minHeight: CallPanel.minHeight,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
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
    this.size = 56,
    this.iconSize = 28,
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
  final AnimationController rippleController;
  final VoidCallback? onTap;
  final bool isVideo;

  const _AnswerButton({
    required this.rippleController,
    this.onTap,
    this.isVideo = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedBuilder(
            animation: rippleController,
            builder: (context, child) {
              return CustomPaint(
                painter: _RippleRingPainter(
                  progress: rippleController.value,
                  color: const Color(0xFF4CAF50),
                ),
                child: child,
              );
            },
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFF4CAF50),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isVideo ? Icons.videocam : Icons.call,
                color: Colors.white,
                size: 28,
              ),
            ),
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
  final double progress;
  final Color color;

  _RippleRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2;

    for (int i = 0; i < 3; i++) {
      final phaseOffset = i / 3.0;
      final p = (progress + phaseOffset) % 1.0;
      final radius = baseRadius + p * 24;
      final opacity = (1.0 - p) * 0.4;
      if (opacity <= 0) continue;
      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_RippleRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
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
            width: 48,
            height: 48,
            child: Stack(
              children: [
                Container(
                  width: 48,
                  height: 48,
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

  const _EncryptionFingerprint({required this.emoji});

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
    final idx = (elapsed / _kCarouselOneMs).floor();
    if (idx >= _kCarouselCount) return widget.emoji[pos];
    return _carouselSequences[pos][idx.clamp(0, _kCarouselCount - 1)];
  }

  @override
  Widget build(BuildContext context) {
    return TelegramTooltip(
      message: 'This call is end-to-end encrypted',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final elapsedMs = _controller.value * _kTotalMs;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
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
            ),
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

  int get _activeBars =>
      quality <= 0 ? 0 : (quality * _barCount / 100).ceil().clamp(0, _barCount);

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
    )..addListener(() => setState(() {}));
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final parentSize = Size(constraints.maxWidth, constraints.maxHeight);

        Offset currentPos;
        if (_isDragging) {
          currentPos = _dragOffset;
        } else if (_snapController.isAnimating) {
          final t = Curves.easeOutCirc.transform(_snapController.value);
          currentPos = Offset.lerp(_snapFrom, _snapTo, t)!;
        } else {
          currentPos = _cornerPosition(parentSize, _corner);
        }

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
            child: Container(
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
            ),
          ),
        );
      },
    );
  }
}

class _OutgoingPreview extends StatelessWidget {
  final Widget videoWidget;
  final double containerHeight;

  const _OutgoingPreview({
    required this.videoWidget,
    required this.containerHeight,
  });

  static const _minSize = Size(360, 120);
  static const _maxSize = Size(1620, 540);
  static const _hMin = 400.0;
  static const _hDefault = 720.0;

  @override
  Widget build(BuildContext context) {
    final t = ((containerHeight - _hMin) / (_hDefault - _hMin)).clamp(0.0, 1.0);
    final w = _minSize.width + (_maxSize.width - _minSize.width) * t;
    final h = _minSize.height + (_maxSize.height - _minSize.height) * t;

    return Center(
      child: Transform(
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
      ),
    );
  }
}

void showCallPanel(
  BuildContext context,
  CallPanelInfo info, {
  String? callId,
  Widget? remoteVideoWidget,
  Widget? selfVideoWidget,
}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (ctx) {
      final effectiveCallId = callId ?? info.callId;
      void closeAndRate() {
        Navigator.of(ctx).pop();
        if (effectiveCallId.isNotEmpty) {
          showCallRatingDialog(context, callId: effectiveCallId);
        }
      }
      return Center(
        child: SizedBox(
          width: CallPanel.defaultWidth,
          height: CallPanel.defaultHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CallPanel(
              info: info,
              onClose: closeAndRate,
              onDecline: () {
                if (effectiveCallId.isNotEmpty) {
                  final engine = ctx.read<EngineService>();
                  final accountId = ctx.read<AppState>().activeAccountId;
                  engine.declineCall(accountId, effectiveCallId);
                }
                Navigator.of(ctx).pop();
              },
              onAccept: () {
                if (effectiveCallId.isNotEmpty) {
                  final engine = ctx.read<EngineService>();
                  final accountId = ctx.read<AppState>().activeAccountId;
                  engine.acceptCall(accountId, effectiveCallId);
                }
              },
              onHangup: () {
                if (effectiveCallId.isNotEmpty) {
                  final engine = ctx.read<EngineService>();
                  final accountId = ctx.read<AppState>().activeAccountId;
                  engine.endCall(accountId, effectiveCallId);
                }
                closeAndRate();
              },
              remoteVideoWidget: remoteVideoWidget,
              selfVideoWidget: selfVideoWidget,
            ),
          ),
        ),
      );
    },
  );
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
    } catch (_) {}
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
