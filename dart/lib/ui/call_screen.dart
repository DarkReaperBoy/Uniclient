import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/engine_models.dart';

enum GroupCallMode { narrow, wide }

enum MuteButtonState { unmuted, muted, forceMuted }

class GroupCallPanel extends StatefulWidget {
  final GroupCallInfo info;
  final String chatTitle;
  final bool isRecording;
  final bool isSelfMuted;
  final bool isForceMuted;
  final bool isRtmp;
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
    this.isRtmp = false,
    this.onLeave,
    this.onToggleMute,
    this.onToggleVideo,
    this.onToggleScreenShare,
    this.onOpenMenu,
    this.videoViewport,
  });

  static const wideModeThreshold = 600.0;
  static const minWidth = 380.0;
  static const defaultWidth = 720.0;
  static const defaultHeight = 540.0;
  static const sidebarWidth = 260.0;

  @override
  State<GroupCallPanel> createState() => _GroupCallPanelState();
}

class _GroupCallPanelState extends State<GroupCallPanel>
    with TickerProviderStateMixin {
  Timer? _durationTimer;
  int _durationSeconds = 0;

  @override
  void initState() {
    super.initState();
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
      if (mounted) setState(() => _durationSeconds++);
    });
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  MuteButtonState get _muteState {
    if (widget.isForceMuted) return MuteButtonState.forceMuted;
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
                  '$count participant${count == 1 ? '' : 's'}',
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

    return SizedBox(
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
  bool shouldRepaint(_BlobPainter old) => true;
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
          opacity: 0.3 + 0.7 * _controller.value,
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
  static const _blobMinRadius = 28.0;
  static const _blobMaxRadius = 33.0;
  static const _minorScale = 0.545;
  static const _majorScale = 0.605;
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

  @override
  Widget build(BuildContext context) {
    final color = _stateColor;
    final blobSize = _blobMaxRadius * 2 + 8;
    final level = _pulseLevel;
    final showBlob = widget.state == MuteButtonState.unmuted && level > 0.001;

    return GestureDetector(
      onTap: widget.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: blobSize,
            height: blobSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (showBlob)
                  CustomPaint(
                    size: Size(blobSize, blobSize),
                    painter: _BlobPainter(
                      majorBlob: _majorBlob,
                      minorBlob: _minorBlob,
                      radius: _blobMinRadius +
                          (_blobMaxRadius - _blobMinRadius) * level,
                      majorScale: _majorScale,
                      minorScale: _minorScale,
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
                      widget.state == MuteButtonState.unmuted
                          ? Icons.mic
                          : Icons.mic_off,
                      key: ValueKey(widget.state),
                      color: Colors.white,
                      size: _iconSize,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              widget.state == MuteButtonState.unmuted ? 'Mute' : 'Unmute',
              key: ValueKey(widget.state == MuteButtonState.unmuted),
              style: const TextStyle(color: Color(0xAAFFFFFF), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
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

void showGroupCallPanel(BuildContext context, GroupCallInfo info,
    {String chatTitle = '',
    bool isRecording = false,
    bool isSelfMuted = false,
    bool isForceMuted = false,
    Widget? videoViewport}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (ctx) {
      final mq = MediaQuery.of(ctx);
      final screenW = mq.size.width;
      final screenH = mq.size.height;
      final w = math.min(GroupCallPanel.defaultWidth, screenW - 32);
      final h = math.min(GroupCallPanel.defaultHeight, screenH - 32);
      return Center(
        child: SizedBox(
          width: w,
          height: h,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GroupCallPanel(
              info: info,
              chatTitle: chatTitle,
              isRecording: isRecording,
              isSelfMuted: isSelfMuted,
              isForceMuted: isForceMuted,
              videoViewport: videoViewport,
              onLeave: () => Navigator.of(ctx).pop(),
              onToggleScreenShare: () => showScreenShareChooser(ctx),
            ),
          ),
        ),
      );
    },
  );
}

// ── §12.8 Minimised Call TopBar ──

enum _CallBarGradientState { active, muted, connecting, forceMuted }

class MinimisedCallBar extends StatefulWidget {
  final String groupName;
  final List<GroupCallParticipant> participants;
  final bool isSelfMuted;
  final bool isForceMuted;
  final bool isConnecting;
  final VoidCallback? onToggleMute;
  final VoidCallback? onHangup;
  final VoidCallback? onTap;

  const MinimisedCallBar({
    super.key,
    required this.groupName,
    this.participants = const [],
    this.isSelfMuted = false,
    this.isForceMuted = false,
    this.isConnecting = false,
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
  _CallBarGradientState _fromState = _CallBarGradientState.connecting;
  _CallBarGradientState _toState = _CallBarGradientState.connecting;

  @override
  void initState() {
    super.initState();
    _gradientAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    _toState = _resolveGradientState();
    _fromState = _toState;
    _startDurationTimer();
  }

  @override
  void didUpdateWidget(MinimisedCallBar old) {
    super.didUpdateWidget(old);
    final newState = _resolveGradientState();
    if (newState != _toState) {
      _fromState = _toState;
      _toState = newState;
      final stateDistance = (_toState.index - _fromState.index).abs();
      _gradientAnim.duration = Duration(
        milliseconds: stateDistance * 300,
      );
      _gradientAnim.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _gradientAnim.dispose();
    super.dispose();
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _durationSeconds++);
    });
  }

  _CallBarGradientState _resolveGradientState() {
    if (widget.isConnecting) return _CallBarGradientState.connecting;
    if (widget.isForceMuted) return _CallBarGradientState.forceMuted;
    if (widget.isSelfMuted) return _CallBarGradientState.muted;
    return _CallBarGradientState.active;
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static List<Color> _gradientColors(_CallBarGradientState state) {
    switch (state) {
      case _CallBarGradientState.active:
        return [const Color(0xFF52CE5B), const Color(0xFF00B151)];
      case _CallBarGradientState.muted:
        return [const Color(0xFF7F8A96), const Color(0xFF6B7684)];
      case _CallBarGradientState.connecting:
        return [const Color(0xFF7F8A96), const Color(0xFF7F8A96)];
      case _CallBarGradientState.forceMuted:
        return [const Color(0xFF9B59B6), const Color(0xFF7B68EE), const Color(0xFF8E44AD)];
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _gradientAnim,
      builder: (context, child) {
        final fromColors = _gradientColors(_fromState);
        final toColors = _gradientColors(_toState);
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
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.groupName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDuration(_durationSeconds),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.participants.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _UserpicStrip(participants: widget.participants),
                ],
                const SizedBox(width: 8),
                _MuteToggle(
                  isMuted: widget.isSelfMuted || widget.isForceMuted,
                  isForceMuted: widget.isForceMuted,
                  onTap: widget.onToggleMute,
                ),
                const SizedBox(width: 4),
                _HangupButton(onTap: widget.onHangup),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
        border: Border.all(color: Colors.white24, width: 1.5),
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

class _MuteToggle extends StatelessWidget {
  final bool isMuted;
  final bool isForceMuted;
  final VoidCallback? onTap;

  const _MuteToggle({
    required this.isMuted,
    this.isForceMuted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: isForceMuted ? null : onTap,
        padding: EdgeInsets.zero,
        iconSize: 18,
        icon: Icon(
          isMuted ? Icons.mic_off : Icons.mic,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _HangupButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _HangupButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        iconSize: 18,
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFFE53935),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        icon: const Icon(
          Icons.call_end,
          color: Colors.white,
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
  final String? thumbnailPath;

  const ScreenShareSource({
    required this.id,
    required this.name,
    required this.isScreen,
    this.thumbnailPath,
  });
}

Future<ScreenShareSource?> showScreenShareChooser(BuildContext context) {
  return showDialog<ScreenShareSource>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => const _ScreenShareChooserDialog(),
  );
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
  }

  static Future<List<ScreenShareSource>> _enumerateWindows() async {
    if (!Platform.isLinux) return [];

    final sessionType = Platform.environment['XDG_SESSION_TYPE'] ?? '';

    if (sessionType == 'wayland') {
      try {
        final result =
            await Process.run('kdotool', ['search', '--name', '']);
        if (result.exitCode == 0) {
          final uuids = (result.stdout as String)
              .trim()
              .split('\n')
              .where((l) => l.isNotEmpty)
              .toList();
          final sources = <ScreenShareSource>[];
          for (final uuid in uuids) {
            try {
              final nr = await Process.run(
                  'kdotool', ['getwindowname', uuid]);
              final name = nr.exitCode == 0
                  ? (nr.stdout as String).trim()
                  : 'Window';
              if (name.isNotEmpty) {
                sources.add(ScreenShareSource(
                    id: uuid, name: name, isScreen: false));
              }
            } catch (_) {}
          }
          return sources;
        }
      } catch (_) {}
    }

    try {
      final result = await Process.run('wmctrl', ['-l']);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).trim().split('\n');
        return lines.where((l) => l.isNotEmpty).map((line) {
          final parts = line.split(RegExp(r'\s+'));
          final id = parts.isNotEmpty ? parts[0] : '';
          final name = parts.length >= 4
              ? parts.sublist(3).join(' ')
              : 'Unknown Window';
          return ScreenShareSource(
              id: id, name: name, isScreen: false);
        }).toList();
      }
    } catch (_) {}

    return [];
  }

  static Future<List<ScreenShareSource>> _enumerateScreens() async {
    if (!Platform.isLinux) {
      return [
        const ScreenShareSource(
            id: 'screen:0', name: 'Full Screen', isScreen: true),
      ];
    }

    try {
      final result =
          await Process.run('xrandr', ['--listmonitors']);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).trim().split('\n');
        final sources = <ScreenShareSource>[];
        for (final line in lines.skip(1)) {
          if (line.trim().isEmpty) continue;
          final match =
              RegExp(r'(\d+):\s+\+?\*?(\S+)\s+(\d+)/\d+x(\d+)')
                  .firstMatch(line);
          if (match != null) {
            final idx = match.group(1)!;
            final name = match.group(2)!;
            final w = match.group(3)!;
            final h = match.group(4)!;
            sources.add(ScreenShareSource(
              id: 'screen:$idx',
              name: '$name (${w}x$h)',
              isScreen: true,
            ));
          }
        }
        if (sources.isNotEmpty) return sources;
      }
    } catch (_) {}

    return [
      const ScreenShareSource(
          id: 'screen:0', name: 'Full Screen', isScreen: true),
    ];
  }

  static Future<bool> _checkPipeWire() async {
    if (!Platform.isLinux) return false;
    try {
      final result = await Process.run('pgrep', ['-x', 'pipewire']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  void _confirm() {
    if (_selected != null) {
      Navigator.of(context).pop(_selected);
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
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF40A7E3)),
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
              activeColor: const Color(0xFF40A7E3),
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
              backgroundColor: const Color(0xFF40A7E3),
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
                  ? const Color(0xFF40A7E3)
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive
                ? const Color(0xFF40A7E3)
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

  const _ScreenSourceThumb({
    required this.source,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
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
                    ? const Color(0xFF40A7E3)
                    : const Color(0x30FFFFFF),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: source.thumbnailPath != null &&
                      File(source.thumbnailPath!).existsSync()
                  ? Image.file(
                      File(source.thumbnailPath!),
                      fit: BoxFit.cover,
                      width: _kThumbW,
                      height: _kThumbH,
                    )
                  : Center(
                      child: Icon(
                        source.isScreen
                            ? Icons.monitor
                            : Icons.web_asset,
                        color: const Color(0x60FFFFFF),
                        size: 48,
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
                    ? const Color(0xFF40A7E3)
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
