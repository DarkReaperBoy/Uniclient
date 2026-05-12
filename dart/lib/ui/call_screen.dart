import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dbus/dbus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../bridge/engine_service.dart';
import '../state/app_state.dart';
import '../theme/telegram_palette.dart';

import '../models/engine_models.dart';

enum GroupCallMode { narrow, wide }

enum MuteButtonState { unmuted, muted, forceMuted }

class GroupCallPanel extends StatefulWidget {
  final GroupCallInfo info;
  final String chatTitle;
  final bool isRecording;
  final bool isSelfMuted;
  final bool isForceMuted;
  final bool isRaisedHand;
  final bool isRtmp;
  final bool isCanManage;
  final DateTime? callStartTime;
  final VoidCallback? onLeave;
  final VoidCallback? onToggleMute;
  final VoidCallback? onToggleVideo;
  final VoidCallback? onToggleScreenShare;
  final VoidCallback? onOpenMenu;
  final Widget? videoViewport;

  const GroupCallPanel({
    super.key,
    required this.info,
    this.chatTitle = '',
    this.isRecording = false,
    this.isSelfMuted = false,
    this.isForceMuted = false,
    this.isRaisedHand = false,
    this.isRtmp = false,
    this.isCanManage = false,
    this.callStartTime,
    this.onLeave,
    this.onToggleMute,
    this.onToggleVideo,
    this.onToggleScreenShare,
    this.onOpenMenu,
    this.videoViewport,
  });

  static const wideModeThreshold = 600.0;
  static const minWidth = 380.0;
  static const defaultWidthNarrow = 380.0;
  static const defaultWidthRtmp = 720.0;
  static const defaultHeight = 520.0;
  static const sidebarWidth = 260.0;

  @override
  State<GroupCallPanel> createState() => _GroupCallPanelState();
}

class _GroupCallPanelState extends State<GroupCallPanel>
    with TickerProviderStateMixin {
  Timer? _durationTimer;
  int _durationSeconds = 0;
  late DateTime _callStartTime;

  @override
  void initState() {
    super.initState();
    _callStartTime = widget.callStartTime ?? DateTime.now();
    _durationSeconds = DateTime.now().difference(_callStartTime).inSeconds;
    if (_durationSeconds < 0) _durationSeconds = 0;
    _startDurationTimer();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _durationSeconds =
              DateTime.now().difference(_callStartTime).inSeconds;
          if (_durationSeconds < 0) _durationSeconds = 0;
        });
      }
    });
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  MuteButtonState get _muteState {
    if (widget.isForceMuted || widget.isRaisedHand) {
      return MuteButtonState.forceMuted;
    }
    if (widget.isSelfMuted) return MuteButtonState.muted;
    return MuteButtonState.unmuted;
  }

  GroupCallMode _resolveMode(double width) {
    if (widget.isRtmp) return GroupCallMode.wide;
    final hasVideoWithFrames =
        widget.videoViewport != null ||
        widget.info.participants.any((p) => p.hasVideo);
    if (hasVideoWithFrames && width >= GroupCallPanel.wideModeThreshold) {
      return GroupCallMode.wide;
    }
    return GroupCallMode.narrow;
  }

  Widget _buildTitleBar() {
    final title =
        widget.chatTitle.isNotEmpty
            ? widget.chatTitle
            : (widget.info.title.isNotEmpty ? widget.info.title : 'Voice Chat');
    final count = widget.info.participantsCount;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0x20FFFFFF), width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.isRecording) ...[
                      _RecordingDot(),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$count participant${count == 1 ? '' : 's'} · ${_formatDuration(_durationSeconds)}',
                  style: const TextStyle(
                    color: Color(0xAAFFFFFF),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          _TitleBarButton(
            icon: Icons.more_vert,
            onTap: widget.onOpenMenu,
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantRow(GroupCallParticipant p) {
    final avatarColor = HSLColor.fromAHSL(
      1.0,
      (p.userId.hashCode.abs() % 360).toDouble(),
      0.5,
      0.45,
    ).toColor();
    final initials =
        p.displayName.isNotEmpty
            ? p.displayName
                .split(' ')
                .where((w) => w.isNotEmpty)
                .take(2)
                .map((w) => w[0].toUpperCase())
                .join()
            : '?';

    Widget avatar;
    if (p.avatarPath.isNotEmpty && File(p.avatarPath).existsSync()) {
      avatar = ClipOval(
        child: Image.file(
          File(p.avatarPath),
          width: 36,
          height: 36,
          fit: BoxFit.cover,
        ),
      );
    } else {
      avatar = CircleAvatar(
        radius: 18,
        backgroundColor: avatarColor,
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _SpeakerBlobAvatar(
            level: p.isSpeaking ? (p.audioLevel > 0 ? p.audioLevel : 0.5) : 0.0,
            isSpeaking: p.isSpeaking,
            child: avatar,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              p.displayName.isNotEmpty ? p.displayName : 'User',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (p.isSpeaking)
            const Icon(Icons.graphic_eq, color: Color(0xFF4DC920), size: 20),
          if (p.isMuted)
            const Icon(Icons.mic_off, color: Color(0x80FFFFFF), size: 18),
          if (p.hasVideo)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.videocam, color: Color(0x80FFFFFF), size: 18),
            ),
        ],
      ),
    );
  }

  Widget _buildParticipantsList() {
    final participants = widget.info.participants;
    if (participants.isEmpty) {
      return const Expanded(
        child: Center(
          child: Text(
            'No participants yet',
            style: TextStyle(color: Color(0x80FFFFFF), fontSize: 14),
          ),
        ),
      );
    }
    return Expanded(
      child: ListView.builder(
        itemCount: participants.length,
        itemBuilder: (context, index) =>
            _buildParticipantRow(participants[index]),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0x20FFFFFF), width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _GroupCallControlButton(
            icon: Icons.screen_share_outlined,
            label: 'Screen',
            onTap: widget.onToggleScreenShare,
          ),
          _GroupCallControlButton(
            icon: Icons.videocam_outlined,
            label: 'Video',
            onTap: widget.onToggleVideo,
          ),
          _GroupCallActionButton(
            icon: Icons.call_end,
            backgroundColor: const Color(0xFFE53935),
            onTap: widget.onLeave,
          ),
          _BigMuteButton(
            state: _muteState,
            onTap: widget.onToggleMute,
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowMode() {
    return Column(
      children: [
        _buildTitleBar(),
        _buildParticipantsList(),
        _buildBottomControls(),
      ],
    );
  }

  Widget _buildWideMode() {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: widget.videoViewport ??
                    Container(
                      color: const Color(0xFF0D1117),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.videocam_off,
                              color: const Color(0x60FFFFFF),
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No video',
                              style: TextStyle(
                                color: Color(0x60FFFFFF),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ),
              _buildBottomControls(),
            ],
          ),
        ),
        Container(
          width: GroupCallPanel.sidebarWidth,
          decoration: const BoxDecoration(
            color: Color(0xFF151B23),
            border: Border(
              left: BorderSide(color: Color(0x20FFFFFF), width: 1),
            ),
          ),
          child: Column(
            children: [
              _buildTitleBar(),
              _buildParticipantsList(),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: GroupCallPanel.minWidth,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1A1A2E), Color(0xFF0F0F1A)],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final mode = _resolveMode(constraints.maxWidth);
              switch (mode) {
                case GroupCallMode.narrow:
                  return _buildNarrowMode();
                case GroupCallMode.wide:
                  return _buildWideMode();
              }
            },
          ),
        ),
      ),
    );
  }
}

class _SpeakerBlobAvatar extends StatefulWidget {
  final double level;
  final bool isSpeaking;
  final Widget child;

  const _SpeakerBlobAvatar({
    required this.level,
    required this.isSpeaking,
    required this.child,
  });

  @override
  State<_SpeakerBlobAvatar> createState() => _SpeakerBlobAvatarState();
}

class _SpeakerBlobAvatarState extends State<_SpeakerBlobAvatar>
    with SingleTickerProviderStateMixin {
  static const _minRadius = 27.0;
  static const _maxRadius = 29.0;
  static const _minorScale = 0.545;
  static const _majorScale = 0.605;
  static const _minorVertices = 6;
  static const _majorVertices = 8;
  static const _userpicMinScale = 0.8;
  static const _levelDuration = Duration(milliseconds: 215);

  late AnimationController _ticker;
  late _BlobState _minorBlob;
  late _BlobState _majorBlob;
  double _currentLevel = 0.0;
  double _targetLevel = 0.0;
  double _levelVelocity = 0.0;
  DateTime _lastLevelUpdate = DateTime.now();

  @override
  void initState() {
    super.initState();
    final rng = math.Random(widget.child.hashCode);
    _minorBlob = _BlobState(_minorVertices, rng);
    _majorBlob = _BlobState(_majorVertices, rng);
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _ticker.addListener(_onTick);
    if (widget.isSpeaking) {
      _targetLevel = widget.level;
      _ticker.repeat();
    }
  }

  @override
  void didUpdateWidget(_SpeakerBlobAvatar old) {
    super.didUpdateWidget(old);
    if (widget.isSpeaking != old.isSpeaking || widget.level != old.level) {
      _targetLevel = widget.isSpeaking ? widget.level : 0.0;
      _lastLevelUpdate = DateTime.now();
      if (widget.isSpeaking && !_ticker.isAnimating) {
        _ticker.repeat();
      }
    }
  }

  void _onTick() {
    final now = DateTime.now();
    final dt = now.difference(_lastLevelUpdate).inMilliseconds /
        _levelDuration.inMilliseconds;
    _lastLevelUpdate = now;

    final diff = _targetLevel - _currentLevel;
    _levelVelocity = diff * dt.clamp(0.0, 1.0);
    _currentLevel = (_currentLevel + _levelVelocity).clamp(0.0, 1.0);

    _minorBlob.advance();
    _majorBlob.advance();

    if (!widget.isSpeaking && _currentLevel < 0.001) {
      _currentLevel = 0.0;
      _ticker.stop();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = _minRadius + (_maxRadius - _minRadius) * _currentLevel;
    final userpicScale =
        _userpicMinScale + (1.0 - _userpicMinScale) * _currentLevel;
    final blobSize = _maxRadius * 2 + 4;

    if (!widget.isSpeaking && _currentLevel < 0.001) {
      return SizedBox(
        width: blobSize,
        height: blobSize,
        child: Center(child: widget.child),
      );
    }

    return RepaintBoundary(
      child: SizedBox(
        width: blobSize,
        height: blobSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(blobSize, blobSize),
              painter: _BlobPainter(
                majorBlob: _majorBlob,
                minorBlob: _minorBlob,
                radius: radius,
                majorScale: _majorScale,
                minorScale: _minorScale,
                color: const Color(0xFF4DC920),
                level: _currentLevel,
              ),
            ),
            Transform.scale(
              scale: userpicScale,
              child: widget.child,
            ),
          ],
        ),
      ),
    );
  }
}

class _BlobState {
  final int vertexCount;
  final List<double> _radii;
  final List<double> _targetRadii;
  final List<double> _angles;
  final math.Random _rng;

  _BlobState(this.vertexCount, this._rng)
      : _radii = List.generate(vertexCount, (_) => 0.9 + _rng.nextDouble() * 0.2),
        _targetRadii = List.generate(vertexCount, (_) => 0.9 + _rng.nextDouble() * 0.2),
        _angles = List.generate(vertexCount, (i) {
          final base = (i / vertexCount) * 2 * math.pi;
          return base + (_rng.nextDouble() - 0.5) * 0.3;
        });

  void advance() {
    for (var i = 0; i < vertexCount; i++) {
      _radii[i] += (_targetRadii[i] - _radii[i]) * 0.12;
      if ((_radii[i] - _targetRadii[i]).abs() < 0.01) {
        _targetRadii[i] = 0.85 + _rng.nextDouble() * 0.3;
      }
      _angles[i] += (_rng.nextDouble() - 0.5) * 0.02;
    }
  }

  List<Offset> getVertices(double radius, double cx, double cy) {
    final verts = <Offset>[];
    for (var i = 0; i < vertexCount; i++) {
      final r = radius * _radii[i];
      verts.add(Offset(
        cx + r * math.cos(_angles[i]),
        cy + r * math.sin(_angles[i]),
      ));
    }
    return verts;
  }
}

class _BlobPainter extends CustomPainter {
  final _BlobState majorBlob;
  final _BlobState minorBlob;
  final double radius;
  final double majorScale;
  final double minorScale;
  final Color color;
  final double level;

  _BlobPainter({
    required this.majorBlob,
    required this.minorBlob,
    required this.radius,
    required this.majorScale,
    required this.minorScale,
    required this.color,
    required this.level,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (level < 0.001) return;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final alpha = (level * 180).round().clamp(0, 180);

    final majorPaint = Paint()
      ..color = color.withAlpha(alpha ~/ 2)
      ..style = PaintingStyle.fill;
    final majorVerts =
        majorBlob.getVertices(radius * majorScale, cx, cy);
    canvas.drawPath(_smoothPath(majorVerts), majorPaint);

    final minorPaint = Paint()
      ..color = color.withAlpha(alpha)
      ..style = PaintingStyle.fill;
    final minorVerts =
        minorBlob.getVertices(radius * minorScale, cx, cy);
    canvas.drawPath(_smoothPath(minorVerts), minorPaint);
  }

  Path _smoothPath(List<Offset> points) {
    if (points.length < 3) return Path();
    final path = Path();
    final n = points.length;

    path.moveTo(
      (points[n - 1].dx + points[0].dx) / 2,
      (points[n - 1].dy + points[0].dy) / 2,
    );

    for (var i = 0; i < n; i++) {
      final next = (i + 1) % n;
      final midX = (points[i].dx + points[next].dx) / 2;
      final midY = (points[i].dy + points[next].dy) / 2;
      path.quadraticBezierTo(
        points[i].dx,
        points[i].dy,
        midX,
        midY,
      );
    }

    path.close();
    return path;
  }

  @override
  bool shouldRepaint(_BlobPainter old) =>
      old.level != level || old.radius != radius || old.color != color;
}

class _RecordingDot extends StatefulWidget {
  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.6 + 0.4 * _controller.value,
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFFE53935),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

class _TitleBarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _TitleBarButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: const Color(0xAAFFFFFF), size: 22),
      ),
    );
  }
}

class _BigMuteButton extends StatefulWidget {
  final MuteButtonState state;
  final VoidCallback? onTap;

  const _BigMuteButton({required this.state, this.onTap});

  @override
  State<_BigMuteButton> createState() => _BigMuteButtonState();
}

class _BigMuteButtonState extends State<_BigMuteButton>
    with SingleTickerProviderStateMixin {
  static const _circleSize = 42.0;
  static const _iconSize = 36.0;
  static const _minorBlobMinRadius = 64.0;
  static const _minorBlobMaxRadius = 74.0;
  static const _majorBlobMinRadius = 67.0;
  static const _majorBlobMaxRadius = 77.0;
  static const _pulsePeriodMs = 430;

  static const _greenColor = Color(0xFF4DC920);
  static const _grayColor = Color(0xFF808B94);
  static const _purpleColor = Color(0xFF7B5EBF);

  late AnimationController _ticker;
  late _BlobState _minorBlob;
  late _BlobState _majorBlob;
  late DateTime _startTime;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(12345);
    _minorBlob = _BlobState(6, rng);
    _majorBlob = _BlobState(8, rng);
    _startTime = DateTime.now();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_onTick);
    if (widget.state == MuteButtonState.unmuted) {
      _ticker.repeat();
    }
  }

  @override
  void didUpdateWidget(_BigMuteButton old) {
    super.didUpdateWidget(old);
    if (widget.state != old.state) {
      if (widget.state == MuteButtonState.unmuted && !_ticker.isAnimating) {
        _startTime = DateTime.now();
        _ticker.repeat();
      } else if (widget.state != MuteButtonState.unmuted &&
          _ticker.isAnimating) {
        _ticker.stop();
      }
      setState(() {});
    }
  }

  void _onTick() {
    _minorBlob.advance();
    _majorBlob.advance();
    setState(() {});
  }

  double get _pulseLevel {
    if (widget.state != MuteButtonState.unmuted) return 0.0;
    final elapsed =
        DateTime.now().difference(_startTime).inMilliseconds;
    return 0.35 + 0.35 * math.sin(elapsed * 2 * math.pi / _pulsePeriodMs);
  }

  Color get _stateColor {
    switch (widget.state) {
      case MuteButtonState.unmuted:
        return _greenColor;
      case MuteButtonState.muted:
        return _grayColor;
      case MuteButtonState.forceMuted:
        return _purpleColor;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _handleTap(BuildContext context) {
    if (widget.state == MuteButtonState.forceMuted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are muted by an admin'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    widget.onTap?.call();
  }

  String get _label {
    switch (widget.state) {
      case MuteButtonState.unmuted:
        return 'Mute';
      case MuteButtonState.muted:
        return 'Unmute';
      case MuteButtonState.forceMuted:
        return 'Raise Hand';
    }
  }

  IconData get _icon {
    switch (widget.state) {
      case MuteButtonState.unmuted:
        return Icons.mic;
      case MuteButtonState.muted:
        return Icons.mic_off;
      case MuteButtonState.forceMuted:
        return Icons.back_hand_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _stateColor;
    final blobSize = _majorBlobMaxRadius * 2 + 8;
    final level = _pulseLevel;
    final showBlob = widget.state == MuteButtonState.unmuted && level > 0.001;

    return GestureDetector(
      onTap: () => _handleTap(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RepaintBoundary(
            child: SizedBox(
              width: blobSize,
              height: blobSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (showBlob)
                    CustomPaint(
                      size: Size(blobSize, blobSize),
                      painter: _BigMuteBlobPainter(
                        majorBlob: _majorBlob,
                        minorBlob: _minorBlob,
                        minorRadius: _minorBlobMinRadius +
                            (_minorBlobMaxRadius - _minorBlobMinRadius) * level,
                        majorRadius: _majorBlobMinRadius +
                            (_majorBlobMaxRadius - _majorBlobMinRadius) * level,
                        color: color,
                        level: level,
                      ),
                    ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                  width: _circleSize,
                  height: _circleSize,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      _icon,
                      key: ValueKey(widget.state),
                      color: Colors.white,
                      size: _iconSize,
                    ),
                  ),
                ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _label,
              key: ValueKey(widget.state),
              style: const TextStyle(color: Color(0xAAFFFFFF), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _BigMuteBlobPainter extends CustomPainter {
  final _BlobState majorBlob;
  final _BlobState minorBlob;
  final double minorRadius;
  final double majorRadius;
  final Color color;
  final double level;

  _BigMuteBlobPainter({
    required this.majorBlob,
    required this.minorBlob,
    required this.minorRadius,
    required this.majorRadius,
    required this.color,
    required this.level,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (level < 0.001) return;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final alpha = (level * 180).round().clamp(0, 180);

    final majorPaint = Paint()
      ..color = color.withAlpha(alpha ~/ 2)
      ..style = PaintingStyle.fill;
    final majorVerts = majorBlob.getVertices(majorRadius, cx, cy);
    canvas.drawPath(_smoothPath(majorVerts), majorPaint);

    final minorPaint = Paint()
      ..color = color.withAlpha(alpha)
      ..style = PaintingStyle.fill;
    final minorVerts = minorBlob.getVertices(minorRadius, cx, cy);
    canvas.drawPath(_smoothPath(minorVerts), minorPaint);
  }

  Path _smoothPath(List<Offset> points) {
    if (points.length < 3) return Path();
    final path = Path();
    final n = points.length;
    path.moveTo(
      (points[n - 1].dx + points[0].dx) / 2,
      (points[n - 1].dy + points[0].dy) / 2,
    );
    for (var i = 0; i < n; i++) {
      final next = (i + 1) % n;
      final midX = (points[i].dx + points[next].dx) / 2;
      final midY = (points[i].dy + points[next].dy) / 2;
      path.quadraticBezierTo(points[i].dx, points[i].dy, midX, midY);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(_BigMuteBlobPainter old) =>
      old.level != level ||
      old.minorRadius != minorRadius ||
      old.majorRadius != majorRadius ||
      old.color != color;
}

class _GroupCallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  const _GroupCallControlButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
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
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Color(0xAAFFFFFF), fontSize: 11),
        ),
      ],
    );
  }
}

class _GroupCallActionButton extends StatelessWidget {
  final IconData icon;
  final Color backgroundColor;
  final VoidCallback? onTap;

  const _GroupCallActionButton({
    required this.icon,
    required this.backgroundColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }
}

void showGroupCallPanel(
  BuildContext context,
  GroupCallInfo info, {
  String chatTitle = '',
  bool isRecording = false,
  bool isSelfMuted = false,
  bool isForceMuted = false,
  bool isRaisedHand = false,
  bool isCanManage = false,
  DateTime? callStartTime,
  VoidCallback? onToggleMute,
  VoidCallback? onToggleVideo,
  Widget? videoViewport,
}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (ctx) {
      var selfMuted = isSelfMuted;
      var forceMuted = isForceMuted;
      var raisedHand = isRaisedHand;
      var cameraEnabled = false;
      final mq = MediaQuery.of(ctx);
      final screenW = mq.size.width;
      final screenH = mq.size.height;
      final panelWidth = info.isRtmp ? GroupCallPanel.defaultWidthRtmp : GroupCallPanel.defaultWidthNarrow;
      final w = math.min(panelWidth, screenW - 32);
      final h = math.min(GroupCallPanel.defaultHeight, screenH - 32);
      return Center(
        child: SizedBox(
          width: w,
          height: h,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: StatefulBuilder(
              builder: (sbCtx, setSbState) {
                return GroupCallPanel(
                  info: info,
                  chatTitle: chatTitle,
                  isRecording: isRecording,
                  isSelfMuted: selfMuted,
                  isForceMuted: forceMuted,
                  isRaisedHand: raisedHand,
                  isCanManage: isCanManage,
                  callStartTime: callStartTime,
                  videoViewport: videoViewport,
                  onLeave: () {
                    if (isCanManage) {
                      _showLeaveOrEndDialog(ctx,
                        onLeave: () => Navigator.of(ctx).pop(),
                        onEndForAll: () async {
                          final engine = sbCtx.read<EngineService>();
                          final accountId = sbCtx.read<AppState>().activeAccountId;
                          final callId = info.callId;
                          if (callId.isNotEmpty) {
                            await engine.endGroupCall(accountId, callId);
                          }
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                      );
                    } else {
                      Navigator.of(ctx).pop();
                    }
                  },
                  onToggleMute: () {
                    if (forceMuted && !raisedHand) {
                      setSbState(() => raisedHand = true);
                    } else if (!forceMuted) {
                      setSbState(() => selfMuted = !selfMuted);
                    }
                    onToggleMute?.call();
                  },
                  onToggleVideo: () {
                    final engine = sbCtx.read<EngineService>();
                    final accountId = sbCtx.read<AppState>().activeAccountId;
                    final callId = info.callId;
                    if (callId.isEmpty) return;
                    cameraEnabled = !cameraEnabled;
                    engine.toggleCamera(accountId, callId, cameraEnabled);
                    onToggleVideo?.call();
                  },
                  onToggleScreenShare: () async {
                    final result = await showScreenShareChooser(sbCtx);
                    if (result != null) {
                      final engine = sbCtx.read<EngineService>();
                      final accountId = sbCtx.read<AppState>().activeAccountId;
                      final callId = info.callId;
                      if (callId.isNotEmpty) {
                        await engine.toggleScreenSharing(accountId, callId, true,
                            sourceId: result.id, withAudio: result.withAudio);
                      }
                    }
                  },
                  onOpenMenu: () {
                    _showGroupCallMenu(ctx);
                  },
                );
              },
            ),
          ),
        ),
      );
    },
  );
}

void _showGroupCallMenu(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1E2530),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.volume_up, color: Colors.white70),
              title: const Text('Sound', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showSoundDevicePicker(context);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.person_add, color: Colors.white70),
              title: const Text('Invite members',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showInviteMembersFromMenu(context);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.settings, color: Colors.white70),
              title: const Text('Settings',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showCallSettingsFromMenu(context);
              },
            ),
          ],
        ),
      );
    },
  );
}

Future<void> _showSoundDevicePicker(BuildContext context) async {
  final appState = context.read<AppState>();
  final devices = <String>['Default'];
  if (Platform.isLinux) {
    try {
      final result = await Process.run('pactl', ['list', 'sinks', 'short']);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).trim().split('\n');
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          final parts = line.split('\t');
          if (parts.length >= 2) {
            final name = parts[1]
                .replaceAll('alsa_output.', '')
                .replaceAll('.analog-stereo', ' (Analog Stereo)')
                .replaceAll('.hdmi-stereo', ' (HDMI Stereo)')
                .replaceAll('_', ' ');
            devices.add(name);
          }
        }
      }
    } catch (_) {}
  } else if (Platform.isMacOS) {
    devices.addAll(['Built-in Output', 'Headphones']);
  } else if (Platform.isWindows) {
    devices.addAll(['Speakers', 'Headphones']);
  }

  if (!context.mounted) return;
  final current = appState.callOutputDevice;
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1E2530),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Output Device',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
            for (final d in devices)
              ListTile(
                leading: Icon(
                  d == current ? Icons.check_circle : Icons.circle_outlined,
                  color: d == current ? const Color(0xFF4DC920) : Colors.white38,
                  size: 20,
                ),
                title: Text(d, style: const TextStyle(color: Colors.white)),
                onTap: () {
                  appState.setCallOutputDevice(d);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      );
    },
  );
}

Future<void> _showInviteMembersFromMenu(BuildContext context) async {
  final engine = context.read<EngineService>();
  final accountId = context.read<AppState>().activeAccountId;

  final contacts = await engine.getContacts(accountId);
  if (!context.mounted || contacts.isEmpty) return;

  final selectedIds = <String>{};
  await showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1E2530),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx2, setSheetState) {
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx2).size.height * 0.6,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Invite Members',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                        ),
                        TextButton(
                          onPressed: selectedIds.isEmpty
                              ? null
                              : () => Navigator.pop(ctx2),
                          child: Text('Invite (${selectedIds.length})',
                              style: TextStyle(
                                  color: selectedIds.isEmpty
                                      ? Colors.white30
                                      : const Color(0xFF4DC920))),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: contacts.length,
                      itemBuilder: (_, i) {
                        final c = contacts[i];
                        final selected = selectedIds.contains(c.userId);
                        return ListTile(
                          leading: Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: selected
                                ? const Color(0xFF4DC920)
                                : Colors.white38,
                          ),
                          title: Text(c.displayName,
                              style:
                                  const TextStyle(color: Colors.white)),
                          onTap: () {
                            setSheetState(() {
                              if (selected) {
                                selectedIds.remove(c.userId);
                              } else {
                                selectedIds.add(c.userId);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  if (selectedIds.isEmpty || !context.mounted) return;

  final result = await engine.createConferenceCall(accountId);
  if (result == null || !context.mounted) return;

  for (final userId in selectedIds) {
    await engine.sendMessage(accountId, userId, result.inviteLink);
  }
}

void _showCallSettingsFromMenu(BuildContext context) {
  final appState = context.read<AppState>();
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1E2530),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx2, setSheetState) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Call Settings',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ),
                SwitchListTile(
                  title: const Text('Noise Suppression',
                      style: TextStyle(color: Colors.white)),
                  value: appState.callNoiseSuppression,
                  activeColor: const Color(0xFF4DC920),
                  onChanged: (v) {
                    setSheetState(() {
                      appState.setCallNoiseSuppression(v);
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.volume_up, color: Colors.white70),
                  title: const Text('Output Device',
                      style: TextStyle(color: Colors.white)),
                  subtitle: Text(appState.callOutputDevice,
                      style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(ctx2);
                    _showSoundDevicePicker(context);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );
    },
  );
}

void _showLeaveOrEndDialog(BuildContext context, {required VoidCallback onLeave, required Future<void> Function() onEndForAll}) {
  showDialog(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: const Color(0xFF1E2530),
        title: const Text('Leave voice chat',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Do you want to leave the voice chat or end it for everyone?',
          style: TextStyle(color: Color(0xCCFFFFFF)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onLeave();
            },
            child: const Text('Leave'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onEndForAll();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('End for all'),
          ),
        ],
      );
    },
  );
}

// ── §34.15 Active Call Top Bar ──

enum _CallBarState { connecting, active, muted, forceMuted }

class MinimisedCallBar extends StatefulWidget {
  final bool isPersonalCall;
  final String peerName;
  final String peerFirstName;
  final List<GroupCallParticipant> participants;
  final bool isSelfMuted;
  final bool isForceMuted;
  final bool isRaisedHand;
  final bool isConnecting;
  final bool isCanManage;
  final int signalQuality;
  final DateTime? callStartTime;
  final double audioLevel;
  final VoidCallback? onToggleMute;
  final VoidCallback? onHangup;
  final VoidCallback? onTap;

  const MinimisedCallBar({
    super.key,
    this.isPersonalCall = false,
    required this.peerName,
    this.peerFirstName = '',
    this.participants = const [],
    this.isSelfMuted = false,
    this.isForceMuted = false,
    this.isRaisedHand = false,
    this.isConnecting = false,
    this.isCanManage = false,
    this.signalQuality = 4,
    this.callStartTime,
    this.audioLevel = 0.0,
    this.onToggleMute,
    this.onHangup,
    this.onTap,
  });

  static const height = 38.0;

  @override
  State<MinimisedCallBar> createState() => _MinimisedCallBarState();
}

class _MinimisedCallBarState extends State<MinimisedCallBar>
    with TickerProviderStateMixin {
  Timer? _durationTimer;
  int _durationSeconds = 0;
  late AnimationController _gradientAnim;
  late AnimationController _muteLineAnim;
  _CallBarState _fromState = _CallBarState.connecting;
  _CallBarState _toState = _CallBarState.connecting;

  @override
  void initState() {
    super.initState();
    _gradientAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      value: 1.0,
    );
    _muteLineAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      value: (widget.isSelfMuted || widget.isForceMuted) ? 1.0 : 0.0,
    );
    _toState = _resolveBarState();
    _fromState = _toState;
    _computeInitialDuration();
    _startDurationTimer();
  }

  void _computeInitialDuration() {
    if (widget.callStartTime != null) {
      _durationSeconds = DateTime.now().difference(widget.callStartTime!).inSeconds;
      if (_durationSeconds < 0) _durationSeconds = 0;
    }
  }

  @override
  void didUpdateWidget(MinimisedCallBar old) {
    super.didUpdateWidget(old);
    final newState = _resolveBarState();
    if (newState != _toState) {
      _fromState = _toState;
      _toState = newState;
      _gradientAnim.forward(from: 0.0);
    }
    final muted = widget.isSelfMuted || widget.isForceMuted;
    if (muted && _muteLineAnim.value < 1.0) {
      _muteLineAnim.forward();
    } else if (!muted && _muteLineAnim.value > 0.0) {
      _muteLineAnim.reverse();
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _gradientAnim.dispose();
    _muteLineAnim.dispose();
    super.dispose();
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _durationSeconds++);
    });
  }

  _CallBarState _resolveBarState() {
    if (widget.isConnecting) return _CallBarState.connecting;
    if (widget.isPersonalCall) {
      return (widget.isSelfMuted) ? _CallBarState.muted : _CallBarState.active;
    }
    if (widget.isForceMuted || widget.isRaisedHand) {
      return _CallBarState.forceMuted;
    }
    if (widget.isSelfMuted) return _CallBarState.muted;
    return _CallBarState.active;
  }

  static String _formatDuration(int seconds) {
    if (seconds >= 3600) {
      final h = seconds ~/ 3600;
      final m = (seconds % 3600) ~/ 60;
      final s = seconds % 60;
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static List<Color> _gradientColors(_CallBarState state, bool isPersonal) {
    if (isPersonal) {
      switch (state) {
        case _CallBarState.active:
          return [const Color(0xFF52CE5B), const Color(0xFF00B151)];
        case _CallBarState.muted:
        case _CallBarState.connecting:
          return [const Color(0xFF7F8A96), const Color(0xFF7F8A96)];
        case _CallBarState.forceMuted:
          return [const Color(0xFF7F8A96), const Color(0xFF7F8A96)];
      }
    }
    switch (state) {
      case _CallBarState.active:
        return [const Color(0xFF52CE5B), const Color(0xFF00B151)];
      case _CallBarState.muted:
        return [const Color(0xFF5B6BBE), const Color(0xFF7B68EE)];
      case _CallBarState.connecting:
        return [const Color(0xFF7F8A96), const Color(0xFF7F8A96)];
      case _CallBarState.forceMuted:
        return [const Color(0xFF9B59B6), const Color(0xFF7B68EE), const Color(0xFF8E44AD)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPersonal = widget.isPersonalCall;
    final showBlobs = !isPersonal && !widget.isConnecting;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _gradientAnim,
          builder: (context, child) {
            final fromColors = _gradientColors(_fromState, isPersonal);
            final toColors = _gradientColors(_toState, isPersonal);
            final t = Curves.easeInOut.transform(_gradientAnim.value);

            final maxLen = math.max(fromColors.length, toColors.length);
            final interpolated = List.generate(maxLen, (i) {
              final fc = fromColors[i.clamp(0, fromColors.length - 1)];
              final tc = toColors[i.clamp(0, toColors.length - 1)];
              return Color.lerp(fc, tc, t)!;
            });

            return Container(
              height: MinimisedCallBar.height,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: interpolated),
              ),
              child: child,
            );
          },
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              left: 41,
              right: 41 + 12,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: widget.onTap,
                child: const SizedBox.expand(),
              ),
            ),
            Row(
              children: [
                _CallBarMuteButton(
                  isMuted: widget.isSelfMuted || widget.isForceMuted,
                  isForceMuted: widget.isForceMuted,
                  muteLineAnimation: _muteLineAnim,
                  onTap: widget.onToggleMute,
                ),
                if (isPersonal) ...[
                  const SizedBox(width: 10),
                  Text(
                    widget.isConnecting
                        ? 'Connecting...'
                        : _formatDuration(_durationSeconds),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _SignalBars(quality: widget.signalQuality),
                ],
                if (!isPersonal && widget.participants.isNotEmpty) ...[
                  _UserpicStrip(participants: widget.participants),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final fullText = widget.isConnecting && !isPersonal
                          ? 'Connecting...'
                          : widget.peerName;
                      final shortText = widget.isConnecting && !isPersonal
                          ? 'Connecting...'
                          : (widget.peerFirstName.isNotEmpty
                              ? widget.peerFirstName
                              : widget.peerName);

                      final style = const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.0,
                      );

                      return Text(
                        constraints.maxWidth > 150 ? fullText : shortText,
                        style: style,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      );
                    },
                  ),
                ),
                if (isPersonal) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'End call',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                _CallBarHangupButton(
                  onTap: widget.onHangup,
                  isCanManage: widget.isCanManage,
                ),
                const SizedBox(width: 12),
              ],
            ),
          ],
        ),
      ),
    ),
    if (showBlobs)
      _LinearBlobsBar(level: widget.audioLevel),
    ],
    );
  }
}

class _LinearBlobsBar extends StatefulWidget {
  final double level;

  const _LinearBlobsBar({this.level = 0.0});

  static const _height = 3.0;
  static const _blobCount = 3;
  static const _segments = [5, 7, 8];

  @override
  State<_LinearBlobsBar> createState() => _LinearBlobsBarState();
}

class _LinearBlobsBarState extends State<_LinearBlobsBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ticker;
  late List<List<double>> _blobRadii;
  late List<List<double>> _blobTargets;
  final _rng = math.Random(42);

  @override
  void initState() {
    super.initState();
    _blobRadii = List.generate(
      _LinearBlobsBar._blobCount,
      (b) => List.generate(
        _LinearBlobsBar._segments[b],
        (_) => 0.8 + _rng.nextDouble() * 0.4,
      ),
    );
    _blobTargets = List.generate(
      _LinearBlobsBar._blobCount,
      (b) => List.generate(
        _LinearBlobsBar._segments[b],
        (_) => 0.8 + _rng.nextDouble() * 0.4,
      ),
    );
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_onTick);
    _ticker.repeat();
  }

  void _onTick() {
    for (var b = 0; b < _LinearBlobsBar._blobCount; b++) {
      for (var i = 0; i < _LinearBlobsBar._segments[b]; i++) {
        _blobRadii[b][i] += (_blobTargets[b][i] - _blobRadii[b][i]) * 0.1;
        if ((_blobRadii[b][i] - _blobTargets[b][i]).abs() < 0.01) {
          _blobTargets[b][i] = 0.7 + _rng.nextDouble() * 0.6;
        }
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, _LinearBlobsBar._height),
      painter: _LinearBlobsPainter(
        blobRadii: _blobRadii,
        level: widget.level,
      ),
    );
  }
}

class _LinearBlobsPainter extends CustomPainter {
  final List<List<double>> blobRadii;
  final double level;

  _LinearBlobsPainter({required this.blobRadii, required this.level});

  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      const Color(0xFF52CE5B).withAlpha(60),
      const Color(0xFF00B151).withAlpha(40),
      const Color(0xFF4DC920).withAlpha(30),
    ];

    for (var b = 0; b < blobRadii.length; b++) {
      final segments = blobRadii[b];
      final segW = size.width / segments.length;
      final paint = Paint()
        ..color = colors[b]
        ..style = PaintingStyle.fill;

      final path = Path();
      path.moveTo(0, size.height);

      for (var i = 0; i < segments.length; i++) {
        final x = (i + 0.5) * segW;
        final h = size.height * segments[i] * (0.3 + level * 0.7);
        final y = size.height - h.clamp(0.0, size.height);
        if (i == 0) {
          path.lineTo(0, y);
        }
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_LinearBlobsPainter old) =>
      old.level != level || old.blobRadii != blobRadii;
}

class _CallBarMuteButton extends StatelessWidget {
  final bool isMuted;
  final bool isForceMuted;
  final Animation<double> muteLineAnimation;
  final VoidCallback? onTap;

  const _CallBarMuteButton({
    required this.isMuted,
    this.isForceMuted = false,
    required this.muteLineAnimation,
    this.onTap,
  });

  void _handleTap(BuildContext context) {
    if (isForceMuted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are muted by an admin'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 41,
      height: 38,
      child: InkWell(
        onTap: () => _handleTap(context),
        borderRadius: BorderRadius.circular(16),
        splashColor: Colors.white24,
        child: AnimatedBuilder(
          animation: muteLineAnimation,
          builder: (context, _) {
            return CustomPaint(
              size: const Size(41, 38),
              painter: _MuteCrossLinePainter(
                progress: muteLineAnimation.value,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MuteCrossLinePainter extends CustomPainter {
  final double progress;

  _MuteCrossLinePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final iconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;

    final micTop = cy - 8;
    final micBottom = cy + 4;
    final micLeft = cx - 4;
    final micRight = cx + 4;
    final micRadius = 4.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(micLeft, micTop, micRight, micBottom),
        Radius.circular(micRadius),
      ),
      iconPaint,
    );

    final stemPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, micBottom), Offset(cx, cy + 9), stemPaint);
    canvas.drawLine(Offset(cx - 3, cy + 9), Offset(cx + 3, cy + 9), stemPaint);

    final arcPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, micBottom), width: 14, height: 10),
      0,
      3.14159,
      false,
      arcPaint,
    );

    if (progress > 0.0) {
      final linePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;

      final from = Offset(cx - 8, cy - 8);
      final to = Offset(cx + 8, cy + 8);
      final current = Offset.lerp(from, to, progress)!;
      canvas.drawLine(from, current, linePaint);
    }
  }

  @override
  bool shouldRepaint(_MuteCrossLinePainter old) => old.progress != progress;
}

class _SignalBars extends StatelessWidget {
  final int quality;

  const _SignalBars({required this.quality});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(19, 12),
      painter: _SignalBarsPainter(activeCount: quality.clamp(0, 4)),
    );
  }
}

class _SignalBarsPainter extends CustomPainter {
  final int activeCount;

  _SignalBarsPainter({required this.activeCount});

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 3.0;
    const skip = 1.0;
    const barCount = 4;
    const heights = [3.0, 6.0, 9.0, 12.0];

    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth + skip);
      final h = heights[i];
      final y = size.height - h;
      final isActive = i < activeCount;

      final paint = Paint()
        ..color = Colors.white.withValues(alpha: isActive ? 1.0 : 0.5)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, h),
          const Radius.circular(0.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SignalBarsPainter old) => old.activeCount != activeCount;
}

class _UserpicStrip extends StatelessWidget {
  final List<GroupCallParticipant> participants;

  const _UserpicStrip({required this.participants});

  static const _size = 28.0;
  static const _overlap = 8.0;

  @override
  Widget build(BuildContext context) {
    final count = math.min(participants.length, 5);
    final totalWidth = count > 0 ? _size + (_size - _overlap) * (count - 1) : 0.0;

    return SizedBox(
      width: totalWidth,
      height: _size,
      child: Stack(
        clipBehavior: Clip.none,
        children: List.generate(count, (i) {
          final p = participants[i];
          return Positioned(
            left: i * (_size - _overlap),
            child: _ParticipantAvatar(
              name: p.displayName,
              avatarPath: p.avatarPath,
              size: _size,
            ),
          );
        }),
      ),
    );
  }
}

class _ParticipantAvatar extends StatelessWidget {
  final String name;
  final String avatarPath;
  final double size;

  const _ParticipantAvatar({
    required this.name,
    required this.avatarPath,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarPath.isNotEmpty;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: 2),
        color: hasAvatar ? null : _colorForName(name),
        image: hasAvatar
            ? DecorationImage(
                image: FileImage(File(avatarPath)),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: hasAvatar
          ? null
          : Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
    );
  }

  static Color _colorForName(String name) {
    final colors = [
      const Color(0xFFE57373),
      const Color(0xFF81C784),
      const Color(0xFF64B5F6),
      const Color(0xFFFFB74D),
      const Color(0xFFBA68C8),
      const Color(0xFF4DB6AC),
      const Color(0xFFF06292),
    ];
    final hash = name.codeUnits.fold<int>(0, (h, c) => h + c);
    return colors[hash % colors.length];
  }
}

class _CallBarHangupButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isCanManage;

  const _CallBarHangupButton({this.onTap, this.isCanManage = false});

  void _handleTap(BuildContext context) {
    if (isCanManage) {
      _showLeaveOrEndDialog(context,
        onLeave: () => onTap?.call(),
        onEndForAll: () async {
          onTap?.call();
        },
      );
    } else {
      onTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 41,
      height: 38,
      child: InkWell(
        onTap: () => _handleTap(context),
        borderRadius: BorderRadius.circular(16),
        splashColor: Colors.white24,
        child: const Center(
          child: Icon(
            Icons.call_end,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}

// ── §12.9 Screen-Share Source Chooser ──

const _kThumbW = 235.0;
const _kThumbH = 165.0;
const _kThumbHGap = 2.0;
const _kThumbVGap = 10.0;

class ScreenShareSource {
  final String id;
  final String name;
  final bool isScreen;
  final bool withAudio;

  const ScreenShareSource({
    required this.id,
    required this.name,
    required this.isScreen,
    this.withAudio = false,
  });

  ScreenShareSource copyWith({bool? withAudio}) => ScreenShareSource(
    id: id,
    name: name,
    isScreen: isScreen,
    withAudio: withAudio ?? this.withAudio,
  );
}

Future<ScreenShareSource?> showScreenShareChooser(BuildContext context) async {
  if (Platform.isLinux) {
    final portalResult = await _tryPortalScreenCast();
    if (portalResult != null) return portalResult;
  }
  if (!context.mounted) return null;
  return showDialog<ScreenShareSource>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => const _ScreenShareChooserDialog(),
  );
}

Future<ScreenShareSource?> _tryPortalScreenCast() async {
  final client = DBusClient.session();
  try {
    final object = DBusRemoteObject(
      client,
      name: 'org.freedesktop.portal.Desktop',
      path: DBusObjectPath('/org/freedesktop/portal/desktop'),
    );

    final uniqueName = client.uniqueName;
    if (uniqueName.isEmpty) return null;
    final senderName = uniqueName.substring(1).replaceAll('.', '_');
    final ts = DateTime.now().millisecondsSinceEpoch;
    final token = 'uc_$ts';
    final sessionToken = 'uc_s_$ts';

    final createReqPath = DBusObjectPath(
        '/org/freedesktop/portal/desktop/request/$senderName/$token');
    final createCompleter = Completer<DBusSignal>();
    final createSub = DBusSignalStream(
      client,
      interface: 'org.freedesktop.portal.Request',
      name: 'Response',
      path: createReqPath,
    ).listen(createCompleter.complete);

    await object.callMethod(
      'org.freedesktop.portal.ScreenCast', 'CreateSession',
      [DBusDict(DBusSignature('s'), DBusSignature('v'), {
        DBusString('handle_token'): DBusVariant(DBusString(token)),
        DBusString('session_handle_token'): DBusVariant(DBusString(sessionToken)),
      })],
      replySignature: DBusSignature('o'),
    );

    final createSig = await createCompleter.future.timeout(const Duration(seconds: 5));
    await createSub.cancel();
    if ((createSig.values[0] as DBusUint32).value != 0) return null;

    final createOpts = createSig.values[1] as DBusDict;
    final sessionHandle = ((createOpts.children[DBusString('session_handle')]
        as DBusVariant).value as DBusObjectPath);

    final selToken = 'uc_sel_$ts';
    final selReqPath = DBusObjectPath(
        '/org/freedesktop/portal/desktop/request/$senderName/$selToken');
    final selCompleter = Completer<DBusSignal>();
    final selSub = DBusSignalStream(
      client,
      interface: 'org.freedesktop.portal.Request',
      name: 'Response',
      path: selReqPath,
    ).listen(selCompleter.complete);

    await object.callMethod(
      'org.freedesktop.portal.ScreenCast', 'SelectSources',
      [sessionHandle, DBusDict(DBusSignature('s'), DBusSignature('v'), {
        DBusString('types'): DBusVariant(DBusUint32(3)),
        DBusString('multiple'): DBusVariant(DBusBoolean(false)),
        DBusString('handle_token'): DBusVariant(DBusString(selToken)),
      })],
      replySignature: DBusSignature('o'),
    );

    final selSig = await selCompleter.future.timeout(const Duration(seconds: 120));
    await selSub.cancel();
    if ((selSig.values[0] as DBusUint32).value != 0) return null;

    final startToken = 'uc_st_$ts';
    final startReqPath = DBusObjectPath(
        '/org/freedesktop/portal/desktop/request/$senderName/$startToken');
    final startCompleter = Completer<DBusSignal>();
    final startSub = DBusSignalStream(
      client,
      interface: 'org.freedesktop.portal.Request',
      name: 'Response',
      path: startReqPath,
    ).listen(startCompleter.complete);

    await object.callMethod(
      'org.freedesktop.portal.ScreenCast', 'Start',
      [sessionHandle, DBusString(''), DBusDict(DBusSignature('s'), DBusSignature('v'), {
        DBusString('handle_token'): DBusVariant(DBusString(startToken)),
      })],
      replySignature: DBusSignature('o'),
    );

    final startSig = await startCompleter.future.timeout(const Duration(seconds: 120));
    await startSub.cancel();
    if ((startSig.values[0] as DBusUint32).value != 0) return null;

    final startOpts = startSig.values[1] as DBusDict;
    final streamsVar = startOpts.children[DBusString('streams')] as DBusVariant;
    final streams = streamsVar.value as DBusArray;
    if (streams.children.isEmpty) return null;

    final first = streams.children.first as DBusStruct;
    final nodeId = (first.children[0] as DBusUint32).value;
    final props = first.children[1] as DBusDict;
    final srcTypeVar = props.children[DBusString('source_type')];
    final srcType = srcTypeVar is DBusVariant
        ? (srcTypeVar.value as DBusUint32).value
        : 1;
    final isScreen = srcType == 1;

    return ScreenShareSource(
      id: 'pipewire:$nodeId',
      name: isScreen ? 'Screen' : 'Window',
      isScreen: isScreen,
    );
  } catch (_) {
    return null;
  } finally {
    await client.close();
  }
}

class _ScreenShareChooserDialog extends StatefulWidget {
  const _ScreenShareChooserDialog();

  @override
  State<_ScreenShareChooserDialog> createState() =>
      _ScreenShareChooserDialogState();
}

class _ScreenShareChooserDialogState
    extends State<_ScreenShareChooserDialog> {
  int _activeTab = 1;
  ScreenShareSource? _selected;
  bool _shareAudio = false;
  bool _hasPipeWire = false;
  List<ScreenShareSource> _windows = [];
  List<ScreenShareSource> _screens = [];
  bool _loading = true;
  final Map<String, Uint8List> _thumbnails = {};

  @override
  void initState() {
    super.initState();
    _enumerate();
  }

  Future<void> _enumerate() async {
    final results = await Future.wait([
      _enumerateWindows(),
      _enumerateScreens(),
      _checkPipeWire(),
    ]);
    if (!mounted) return;
    setState(() {
      _windows = results[0] as List<ScreenShareSource>;
      _screens = results[1] as List<ScreenShareSource>;
      _hasPipeWire = results[2] as bool;
      _loading = false;
      if (_screens.isNotEmpty) _selected = _screens.first;
    });
    _captureThumbnails();
  }

  Future<void> _captureThumbnails() async {
    if (!Platform.isLinux) return;
    final allSources = [..._screens, ..._windows];
    final futures = allSources.map((source) async {
      final bytes = await _captureSourceThumb(source);
      if (bytes != null && mounted) {
        setState(() => _thumbnails[source.id] = bytes);
      }
    });
    await Future.wait(futures);
  }

  static Future<Uint8List?> _captureSourceThumb(ScreenShareSource source) async {
    try {
      final w = _kThumbW.toInt() * 2;
      final h = _kThumbH.toInt() * 2;
      if (source.isScreen) {
        final result = await Process.run(
          'import',
          ['-window', 'root', '-resize', '${w}x$h!', 'png:-'],
          stdoutEncoding: null,
        ).timeout(const Duration(seconds: 3));
        if (result.exitCode == 0 && (result.stdout as List<int>).isNotEmpty) {
          return Uint8List.fromList(result.stdout as List<int>);
        }
      } else {
        final wid = source.id.replaceFirst('window:', '');
        if (wid.isEmpty || wid == '0') return null;
        final result = await Process.run(
          'import',
          ['-window', wid, '-resize', '${w}x$h!', 'png:-'],
          stdoutEncoding: null,
        ).timeout(const Duration(seconds: 3));
        if (result.exitCode == 0 && (result.stdout as List<int>).isNotEmpty) {
          return Uint8List.fromList(result.stdout as List<int>);
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<List<ScreenShareSource>> _enumerateWindows() async {
    if (!Platform.isLinux) {
      if (Platform.isMacOS || Platform.isWindows) {
        return [const ScreenShareSource(id: 'window:0', name: 'All Windows', isScreen: false)];
      }
      return [];
    }
    final windows = <ScreenShareSource>[];
    try {
      final result = await Process.run('wmctrl', ['-l']);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).trim().split('\n');
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          final allParts = line.split(RegExp(r'\s+'));
          if (allParts.length >= 4) {
            final wid = allParts[0];
            final title = allParts.sublist(3).join(' ');
            if (title.isNotEmpty && title != 'N/A') {
              windows.add(ScreenShareSource(
                  id: 'window:$wid', name: title, isScreen: false));
            }
          }
        }
      }
    } catch (_) {}
    if (windows.isNotEmpty) return windows;
    try {
      final result = await Process.run('xdotool', ['search', '--name', '']);
      if (result.exitCode == 0) {
        final ids = (result.stdout as String).trim().split('\n');
        for (final id in ids.take(20)) {
          if (id.trim().isEmpty) continue;
          try {
            final nameResult = await Process.run('xdotool', ['getwindowname', id.trim()]);
            if (nameResult.exitCode == 0) {
              final name = (nameResult.stdout as String).trim();
              if (name.isNotEmpty) {
                windows.add(ScreenShareSource(
                    id: 'window:$id', name: name, isScreen: false));
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    return windows;
  }

  static Future<List<ScreenShareSource>> _enumerateScreens() async {
    final displays = ui.PlatformDispatcher.instance.displays;
    if (displays.isNotEmpty) {
      return displays.map((d) {
        final w = d.size.width ~/ d.devicePixelRatio;
        final h = d.size.height ~/ d.devicePixelRatio;
        return ScreenShareSource(
          id: 'screen:${d.id}',
          name: 'Screen ${d.id} (${w}x$h)',
          isScreen: true,
        );
      }).toList();
    }
    return [
      const ScreenShareSource(
          id: 'screen:0', name: 'Full Screen', isScreen: true),
    ];
  }

  static Future<bool> _checkPipeWire() async {
    if (!Platform.isLinux) return false;
    final client = DBusClient.session();
    try {
      final object = DBusRemoteObject(
        client,
        name: 'org.freedesktop.portal.Desktop',
        path: DBusObjectPath('/org/freedesktop/portal/desktop'),
      );
      await object.getProperty(
        'org.freedesktop.portal.ScreenCast', 'AvailableSourceTypes',
        signature: DBusSignature('u'),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      await client.close();
    }
  }

  void _confirm() {
    if (_selected != null) {
      Navigator.of(context).pop(_selected!.copyWith(withAudio: _shareAudio));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final dialogW = math.min(640.0, mq.size.width - 48);
    final dialogH = math.min(480.0, mq.size.height - 48);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: dialogW,
          height: dialogH,
          decoration: BoxDecoration(
            color: const Color(0xFF1E2530),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(100),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildHeader(),
              _buildTabs(),
              Expanded(child: _buildGrid()),
              if (Platform.isLinux && _hasPipeWire) _buildAudioCheckbox(),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: Color(0x20FFFFFF), width: 1)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Choose what to share',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
                Icons.close, color: Color(0xAAFFFFFF), size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: Color(0x10FFFFFF), width: 1)),
      ),
      child: Row(
        children: [
          _SourceTab(
            label: 'Windows',
            isActive: _activeTab == 0,
            onTap: () => setState(() {
              _activeTab = 0;
              _selected =
                  _windows.isNotEmpty ? _windows.first : null;
            }),
          ),
          const SizedBox(width: 24),
          _SourceTab(
            label: 'Full Screen',
            isActive: _activeTab == 1,
            onTap: () => setState(() {
              _activeTab = 1;
              _selected =
                  _screens.isNotEmpty ? _screens.first : null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: context.palette.windowBgActive),
      );
    }

    final sources = _activeTab == 0 ? _windows : _screens;
    if (sources.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _activeTab == 0 ? Icons.web_asset : Icons.monitor,
              color: const Color(0x40FFFFFF),
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              _activeTab == 0
                  ? 'No windows found'
                  : 'No screens found',
              style: const TextStyle(
                  color: Color(0x80FFFFFF), fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: _kThumbW + _kThumbHGap,
          mainAxisExtent: _kThumbH + 28 + _kThumbVGap,
          crossAxisSpacing: _kThumbHGap,
          mainAxisSpacing: _kThumbVGap,
        ),
        itemCount: sources.length,
        itemBuilder: (context, index) {
          final source = sources[index];
          final isSelected = _selected?.id == source.id;
          return _ScreenSourceThumb(
            source: source,
            isSelected: isSelected,
            thumbnail: _thumbnails[source.id],
            onTap: () => setState(() => _selected = source),
            onDoubleTap: () {
              _selected = source;
              _confirm();
            },
          );
        },
      ),
    );
  }

  Widget _buildAudioCheckbox() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: _shareAudio,
              onChanged: (v) =>
                  setState(() => _shareAudio = v ?? false),
              activeColor: context.palette.windowBgActive,
              side: const BorderSide(color: Color(0x80FFFFFF)),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Share audio',
            style: TextStyle(
                color: Color(0xCCFFFFFF), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(
            top: BorderSide(color: Color(0x20FFFFFF), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(
                  color: Color(0xAAFFFFFF), fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _selected != null ? _confirm : null,
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.windowBgActive,
              disabledBackgroundColor: const Color(0x40FFFFFF),
            ),
            child: const Text('Share'),
          ),
        ],
      ),
    );
  }
}

class _SourceTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _SourceTab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive
                  ? context.palette.windowBgActive
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive
                ? context.palette.windowBgActive
                : const Color(0xAAFFFFFF),
            fontSize: 14,
            fontWeight:
                isActive ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _ScreenSourceThumb extends StatelessWidget {
  final ScreenShareSource source;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final Uint8List? thumbnail;

  const _ScreenSourceThumb({
    required this.source,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
    this.thumbnail,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: _kThumbW,
            height: _kThumbH,
            decoration: BoxDecoration(
              color: const Color(0xFF2A3140),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected
                    ? context.palette.windowBgActive
                    : const Color(0x30FFFFFF),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: thumbnail != null
                  ? Image.memory(
                      thumbnail!,
                      width: _kThumbW,
                      height: _kThumbH,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    )
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: source.isScreen
                              ? [const Color(0xFF1A2233), const Color(0xFF2A3344)]
                              : [const Color(0xFF1E2A3A), const Color(0xFF263344)],
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            source.isScreen ? Icons.monitor : Icons.web_asset,
                            color: const Color(0x80FFFFFF),
                            size: 32,
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              source.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0x80FFFFFF),
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: _kThumbW,
            child: Text(
              source.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected
                    ? context.palette.windowBgActive
                    : const Color(0xCCFFFFFF),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
