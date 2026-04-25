import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/engine_models.dart';

enum GroupCallMode { narrow, wide }

class GroupCallPanel extends StatefulWidget {
  final GroupCallInfo info;
  final String chatTitle;
  final bool isRecording;
  final bool isSelfMuted;
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
          avatar,
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
          _GroupCallControlButton(
            icon: widget.isSelfMuted ? Icons.mic_off : Icons.mic,
            label: widget.isSelfMuted ? 'Unmute' : 'Mute',
            isActive: widget.isSelfMuted,
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
              videoViewport: videoViewport,
              onLeave: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      );
    },
  );
}
