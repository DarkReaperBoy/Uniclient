import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../bridge/engine_service.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../theme/telegram_palette.dart';
import 'confirm_box.dart' show showScreenShareChooser;
import 'shell.dart' show UniClientShell;

import '../models/engine_models.dart';
import 'package:uniclient/utils/debug.dart';

enum GroupCallMode { narrow, wide }

enum MuteButtonState { connecting, unmuted, muted, forceMuted }

class GroupCallPanel extends StatefulWidget {
  final GroupCallInfo info;
  final String chatTitle;
  final bool isRecording;
  final bool isSelfMuted;
  final bool isForceMuted;
  final bool isRaisedHand;
  final bool isRtmp;
  final bool isCanManage;
  final bool isConnecting;
  final DateTime? callStartTime;
  final VoidCallback? onLeave;
  final VoidCallback? onToggleMute;
  final VoidCallback? onToggleVideo;
  final VoidCallback? onToggleScreenShare;
  final VoidCallback? onOpenMenu;
  final VoidCallback? onToggleMessages;
  final ValueChanged<String>? onSendMessage;
  final Widget? videoViewport;
  final bool isVideoActive;
  final bool isScreenShareActive;
  final bool isMessagesVisible;
  final int scheduleDate;
  final bool scheduleStartSubscribed;
  final List<CachedMessage> callMessages;

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
    this.isConnecting = false,
    this.isVideoActive = false,
    this.isScreenShareActive = false,
    this.isMessagesVisible = false,
    this.scheduleDate = 0,
    this.scheduleStartSubscribed = false,
    this.callStartTime,
    this.onLeave,
    this.onToggleMute,
    this.onToggleVideo,
    this.onToggleScreenShare,
    this.onOpenMenu,
    this.onToggleMessages,
    this.onSendMessage,
    this.videoViewport,
    this.callMessages = const [],
  });

  static const wideModeThreshold = 600.0;
  static const minWidth = 380.0;
  static const defaultWidthNarrow = 380.0;
  static const defaultWidthRtmp = 720.0;
  static const defaultHeight = 520.0;
  static const defaultHeightRtmp = 580.0;
  static const sidebarWidth = 204.0;

  @override
  State<GroupCallPanel> createState() => _GroupCallPanelState();
}

class _GroupCallPanelState extends State<GroupCallPanel>
    with TickerProviderStateMixin {
  Timer? _durationTimer;
  Timer? _audioLevelTimer;
  int _durationSeconds = 0;
  late DateTime _callStartTime;
  final _validAvatarPaths = <String>{};
  final _messageController = TextEditingController();
  final _messageFocusNode = FocusNode();
  final _chatScrollController = ScrollController();
  final _panelFocusNode = FocusNode();

  double _selfAudioLevel = 0.0;
  StreamSubscription<GroupCallStateEvent>? _callStateSub;
  Map<String, double> _participantLevels = {};
  Map<String, bool> _participantSpeaking = {};
  bool _isRecording = false;
  bool _isPushToTalk = false;
  Timer? _pushToTalkTimer;

  @override
  void initState() {
    super.initState();
    _isRecording = widget.isRecording;
    _callStartTime = widget.callStartTime ?? DateTime.now();
    _durationSeconds = DateTime.now().difference(_callStartTime).inSeconds;
    if (_durationSeconds < 0) _durationSeconds = 0;
    _startDurationTimer();
    _cacheAvatarPaths();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAudioLevelPolling();
      _subscribeToCallState();
    });
  }

  @override
  void didUpdateWidget(GroupCallPanel old) {
    super.didUpdateWidget(old);
    if (widget.info.participants != old.info.participants) {
      _cacheAvatarPaths();
    }
    if (widget.isRecording != old.isRecording) {
      _isRecording = widget.isRecording;
    }
    if (_isPushToTalk && (widget.isForceMuted || widget.isSelfMuted)) {
      _isPushToTalk = false;
      _pushToTalkTimer?.cancel();
      _pushToTalkTimer = null;
    }
    if (widget.callMessages.length > old.callMessages.length && widget.isMessagesVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_chatScrollController.hasClients) {
          _chatScrollController.animateTo(
            _chatScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _cacheAvatarPaths() {
    final paths = widget.info.participants
        .map((p) => p.avatarPath)
        .where((p) => p.isNotEmpty)
        .toSet();
    for (final path in paths) {
      if (!_validAvatarPaths.contains(path)) {
        File(path).exists().then((exists) {
          if (exists && mounted) {
            setState(() => _validAvatarPaths.add(path));
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _audioLevelTimer?.cancel();
    _pushToTalkTimer?.cancel();
    _callStateSub?.cancel();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _chatScrollController.dispose();
    _panelFocusNode.dispose();
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

  void _startAudioLevelPolling() {
    _audioLevelTimer?.cancel();
    _audioLevelTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      if (!mounted) return;
      final callId = widget.info.callId;
      if (callId.isEmpty) return;
      try {
        final engine = context.read<EngineService>();
        final accountId = context.read<AppState>().activeAccountId;
        final results = await Future.wait([
          engine.getCallSoundPeak(accountId, callId),
          engine.getGroupCallParticipantLevels(accountId, widget.info.chatId),
        ]);
        if (!mounted) return;
        final level = results[0] as double;
        final pLevels = results[1] as Map<String, double>;
        bool needsRebuild = false;
        if ((_selfAudioLevel - level).abs() > 0.01) {
          _selfAudioLevel = level;
          needsRebuild = true;
        }
        if (pLevels.isNotEmpty) {
          for (final entry in pLevels.entries) {
            final old = _participantLevels[entry.key] ?? 0.0;
            if ((old - entry.value).abs() > 0.01) {
              needsRebuild = true;
              break;
            }
          }
          if (needsRebuild) {
            _participantLevels = pLevels;
            for (final entry in pLevels.entries) {
              _participantSpeaking[entry.key] = entry.value > 0.01;
            }
          }
        }
        if (needsRebuild) setState(() {});
      } catch (e) {
        Debug.log('call_screen', 'final engine = context.read<EngineService>(): $e');
      }
    });
  }

  void _subscribeToCallState() {
    final engine = context.read<EngineService>();
    _callStateSub = engine.onGroupCallState.listen((event) {
      if (!mounted) return;
      if (event.info.callId != widget.info.callId) return;

      final newRecording = event.info.isRecording;
      if (newRecording != _isRecording) {
        _isRecording = newRecording;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(newRecording ? 'Recording started' : 'Recording saved'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }

      if (mounted) {
        setState(() {
          for (final p in event.info.participants) {
            _participantSpeaking[p.userId] = p.isSpeaking;
          }
        });
      }
    });
  }

  String _formatDuration(int seconds) {
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

  // Matches an RTMP space-hold, or the user-configured push-to-talk shortcut.
  bool _isPttKey(KeyEvent event, AppState appState) {
    if (widget.isRtmp && event.logicalKey == LogicalKeyboardKey.space) {
      return true;
    }
    if (appState.callPushToTalk) {
      final sc = appState.callPttShortcut;
      if (sc.isEmpty || sc == 'Space') {
        return event.logicalKey == LogicalKeyboardKey.space;
      }
      final keyLabel = sc.split('+').last;
      return event.logicalKey.keyLabel.toLowerCase() == keyLabel.toLowerCase();
    }
    return false;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final appState = context.read<AppState>();
    if (!widget.isRtmp && !appState.callPushToTalk) {
      return KeyEventResult.ignored;
    }
    if (!_isPttKey(event, appState)) return KeyEventResult.ignored;
    if (widget.isForceMuted) return KeyEventResult.handled;
    final releaseDelay = Duration(milliseconds: appState.callPttDelay);
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _pushToTalkTimer?.cancel();
      _pushToTalkTimer = null;
      if (!_isPushToTalk && widget.isSelfMuted) {
        _isPushToTalk = true;
        widget.onToggleMute?.call();
      }
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent && _isPushToTalk) {
      _pushToTalkTimer?.cancel();
      _pushToTalkTimer = Timer(releaseDelay, () {
        if (_isPushToTalk && mounted) {
          _isPushToTalk = false;
          if (!widget.isSelfMuted) {
            widget.onToggleMute?.call();
          }
        }
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  MuteButtonState get _muteState {
    // Scheduled state is handled separately (via _isScheduled in the button);
    // before the call instance connects, AyuGram shows a gray "Connecting…".
    if (widget.isConnecting && widget.scheduleDate == 0) {
      return MuteButtonState.connecting;
    }
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
                    if (_isRecording) ...[
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
    if (p.avatarPath.isNotEmpty && _validAvatarPaths.contains(p.avatarPath)) {
      avatar = ClipOval(
        child: Image.file(
          File(p.avatarPath),
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          cacheWidth: 72,
          cacheHeight: 72,
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

    final liveLevel = _participantLevels[p.userId] ?? p.audioLevel;
    final liveSpeaking = _participantSpeaking[p.userId] ?? p.isSpeaking;

    return GestureDetector(
      onLongPress: () => _showParticipantMenu(context, p),
      onSecondaryTapUp: (details) => _showParticipantMenu(context, p, position: details.globalPosition),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _SpeakerBlobAvatar(
              level: liveSpeaking ? (liveLevel > 0 ? liveLevel : 0.5) : 0.0,
              isSpeaking: liveSpeaking,
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
            if (liveSpeaking)
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
      ),
    );
  }

  void _showParticipantMenu(BuildContext context, GroupCallParticipant p, {Offset? position}) {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final chatState = context.read<ChatState>();
    final accountId = appState.activeAccountId;
    final selfUserId = appState.activeAccount?.selfUserId ?? '';
    final callId = widget.info.callId;
    if (callId.isEmpty) return;
    final isSelf = p.userId == selfUserId;

    final items = <PopupMenuEntry<String>>[];

    // View profile / Send message — shown for every non-self participant.
    if (!isSelf) {
      items.add(const PopupMenuItem(value: 'profile', child: Text('View profile')));
      items.add(const PopupMenuItem(value: 'message', child: Text('Send message')));
    }

    // Admin server-side mute/unmute.
    if (!p.isMuted && widget.isCanManage) {
      items.add(const PopupMenuItem(value: 'mute', child: Text('Mute')));
    } else if (p.isMuted && widget.isCanManage) {
      items.add(const PopupMenuItem(value: 'unmute', child: Text('Unmute')));
    }

    // Local "Mute for me" / "Unmute for me" — available to EVERY user, driven
    // by mutedByMe (AyuGram mute_for_me). Implemented via per-listener volume.
    if (!isSelf) {
      final mutedForMe = p.mutedByMe || p.volume == 0;
      items.add(PopupMenuItem(
        value: mutedForMe ? 'unmute_for_me' : 'mute_for_me',
        child: Text(mutedForMe ? 'Unmute for me' : 'Mute for me'),
      ));
    }

    items.add(PopupMenuItem(
      value: 'volume',
      child: Text('Volume: ${(p.volume / 100).round()}%'),
    ));

    if (widget.isCanManage && !isSelf) {
      items.add(const PopupMenuDivider());
      items.add(const PopupMenuItem(
        value: 'kick',
        child: Text('Remove from call', style: TextStyle(color: Colors.redAccent)),
      ));
    }

    if (items.isEmpty) return;

    final pos = position ?? Offset.zero;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      color: const Color(0xFF1E2530),
      items: items,
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'profile':
          // Leave the panel up (call keeps running via the minimised bar) and
          // open the user's profile in the main UI.
          Navigator.of(context).pop();
          chatState.openChatById(p.userId);
          UniClientShell.openInfoRequest?.call();
        case 'message':
          Navigator.of(context).pop();
          chatState.openChatById(p.userId);
        case 'mute':
          engine.muteGroupCallParticipant(accountId, callId, p.userId, true);
        case 'unmute':
          engine.muteGroupCallParticipant(accountId, callId, p.userId, false);
        case 'mute_for_me':
          engine.setGroupCallParticipantVolume(accountId, callId, p.userId, 0);
        case 'unmute_for_me':
          engine.setGroupCallParticipantVolume(accountId, callId, p.userId, 10000);
        case 'volume':
          _showVolumeSlider(context, p, callId: callId);
        case 'kick':
          engine.kickGroupCallParticipant(accountId, callId, p.userId);
      }
    });
  }

  void _showVolumeSlider(BuildContext context, GroupCallParticipant p, {required String callId}) {
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    var volume = p.volume.clamp(0, 20000).toDouble();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF1E2530),
          title: Text(p.displayName, style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${(volume / 100).round()}%',
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
              Slider(
                value: volume,
                min: 0,
                max: 20000,
                divisions: 200,
                activeColor: const Color(0xFF3390EC),
                onChanged: (v) => setDlgState(() => volume = v),
                onChangeEnd: (v) {
                  engine.setGroupCallParticipantVolume(
                    accountId, callId, p.userId, v.round(),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatPanel() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: widget.isMessagesVisible
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: _buildMessagesList(),
                ),
                _buildMessageInput(),
              ],
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildMessagesList() {
    if (widget.callMessages.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Center(
          child: Text(
            'No messages yet',
            style: TextStyle(color: Color(0x60FFFFFF), fontSize: 13),
          ),
        ),
      );
    }
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white, Colors.white],
          stops: [0.0, 0.06, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _chatScrollController,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: widget.callMessages.length,
        reverse: false,
        shrinkWrap: true,
        itemBuilder: (context, index) {
          final msg = widget.callMessages[index];
          return _CallChatBubble(message: msg);
        },
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF151B23),
        border: Border(top: BorderSide(color: Color(0x20FFFFFF), width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              focusNode: _messageFocusNode,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Write a message...',
                hintStyle: TextStyle(color: Color(0x60FFFFFF)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Color(0xFF3390EC), size: 20),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    widget.onSendMessage?.call(text);
    _messageController.clear();
  }

  Widget _buildScheduledOverlay() {
    if (widget.scheduleDate == 0) return const SizedBox.shrink();
    final scheduleTime = DateTime.fromMillisecondsSinceEpoch(widget.scheduleDate * 1000);
    final now = DateTime.now();
    final diff = scheduleTime.difference(now);

    final isLate = diff.isNegative;
    final absDiff = isLate ? now.difference(scheduleTime) : diff;
    final countdownText = _formatDuration(absDiff.inSeconds);
    final startsInText = isLate ? 'Late by' : 'Starts in';

    final whenText = _formatScheduleWhen(scheduleTime);

    return SizedBox(
      height: 200,
      child: Stack(
        children: [
          Positioned(
            left: 0, right: 0, top: 10,
            child: Text(
              startsInText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Positioned(
            left: 0, right: 0, top: 52,
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [
                  Color(0xFFC65493),
                  Color(0xFF7A6AF1),
                  Color(0xFF5F95E8),
                ],
                stops: [0.0, 0.7, 1.0],
              ).createShader(bounds),
              child: Text(
                countdownText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 64,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0, right: 0, top: 160,
            child: Text(
              whenText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatScheduleWhen(DateTime scheduleTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final scheduleDay = DateTime(scheduleTime.year, scheduleTime.month, scheduleTime.day);
    final time = '${scheduleTime.hour.toString().padLeft(2, '0')}:${scheduleTime.minute.toString().padLeft(2, '0')}';

    if (scheduleDay == today) {
      return 'Today at $time';
    } else if (scheduleDay == tomorrow) {
      return 'Tomorrow at $time';
    }
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[scheduleTime.month - 1]} ${scheduleTime.day} at $time';
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

  Widget _buildBottomControls({bool wide = false}) {
    // Narrow mode is a fixed 380px panel. The 5 buttons (68px each) plus 6 even
    // gaps must span the full width with NO horizontal inset — matching AyuGram's
    // narrow 5-button layout (calls_group_panel.cpp updateButtonsGeometry, the
    // `five` branch: fullWidth = groupCallWidth = 380px,
    // buttonSkip = (380 - 5*68) / 6 ≈ 6.67px), which spaceEvenly reproduces as its
    // 6 equal gaps. A 24px side inset would make 5*68 + 48 = 388px > 380px and
    // paint the RenderFlex overflow stripe over the mute button (hiding the
    // transient "Connecting…" label). Wide mode lives in the wider video column,
    // so it keeps the 24px inset.
    final hPad = wide ? 24.0 : 0.0;
    return Container(
      padding: EdgeInsets.fromLTRB(hPad, 16, hPad, wide ? 108 : 113),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0x20FFFFFF), width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _GroupCallControlButton(
            icon: Icons.chat_bubble_outline,
            label: 'Chat',
            isActive: widget.isMessagesVisible,
            onTap: widget.onToggleMessages,
          ),
          _GroupCallControlButton(
            icon: Icons.screen_share_outlined,
            label: 'Screen',
            isActive: widget.isScreenShareActive,
            onTap: widget.onToggleScreenShare,
          ),
          _GroupCallControlButton(
            icon: Icons.videocam_outlined,
            label: 'Video',
            isActive: widget.isVideoActive,
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
            scheduleDate: widget.scheduleDate,
            isCanManage: widget.isCanManage,
            scheduleStartSubscribed: widget.scheduleStartSubscribed,
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowMode() {
    return Column(
      children: [
        _buildTitleBar(),
        if (widget.scheduleDate > 0)
          Expanded(child: _buildScheduledOverlay())
        else
          _buildParticipantsList(),
        _buildChatPanel(),
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
              _buildBottomControls(wide: true),
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
              if (widget.scheduleDate > 0)
                Expanded(child: _buildScheduledOverlay())
              else
                _buildParticipantsList(),
              _buildChatPanel(),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _panelFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: ConstrainedBox(
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
      ),
    );
  }
}

class _CallChatBubble extends StatelessWidget {
  final CachedMessage message;

  const _CallChatBubble({required this.message});

  static const _nameColors = [
    Color(0xFFFC5C51), // red
    Color(0xFFFA790F), // orange
    Color(0xFF895DD5), // purple
    Color(0xFF0FB297), // teal
    Color(0xFF27A8EA), // blue
    Color(0xFFD554B7), // pink
  ];

  @override
  Widget build(BuildContext context) {
    final nameColor = _nameColors[message.senderColorId.abs() % _nameColors.length];
    final time = DateTime.fromMillisecondsSinceEpoch(message.timestamp * 1000);
    final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: const Color(0xCC1E2530),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    message.senderName.isNotEmpty ? message.senderName : 'User',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: nameColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (message.senderRank.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    message.senderRank.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Text(
                  timeStr,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              message.contentText,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
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
  static const _minorBlobRadius = 27.0;
  static const _majorBlobRadius = 29.0;
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

    const avatarSize = 36.0;

    if (!widget.isSpeaking && _currentLevel < 0.001) {
      return SizedBox(
        width: avatarSize,
        height: avatarSize,
        child: Center(child: widget.child),
      );
    }

    return RepaintBoundary(
      child: SizedBox(
        width: avatarSize,
        height: avatarSize,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              left: -(blobSize - avatarSize) / 2,
              top: -(blobSize - avatarSize) / 2,
              right: -(blobSize - avatarSize) / 2,
              bottom: -(blobSize - avatarSize) / 2,
              child: CustomPaint(
                size: Size(blobSize, blobSize),
                painter: _BlobPainter(
                  majorBlob: _majorBlob,
                  minorBlob: _minorBlob,
                  majorRadius: _majorBlobRadius,
                  minorRadius: _minorBlobRadius,
                  color: const Color(0xFF4DC920),
                  level: _currentLevel,
                ),
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
  final double majorRadius;
  final double minorRadius;
  final Color color;
  final double level;

  _BlobPainter({
    required this.majorBlob,
    required this.minorBlob,
    required this.majorRadius,
    required this.minorRadius,
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
  final int scheduleDate;
  final bool isCanManage;
  final bool scheduleStartSubscribed;

  const _BigMuteButton({
    required this.state,
    this.onTap,
    this.scheduleDate = 0,
    this.isCanManage = false,
    this.scheduleStartSubscribed = false,
  });

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
  static const _hideBlobsDuration = Duration(milliseconds: 500);

  late AnimationController _ticker;
  late _BlobState _minorBlob;
  late _BlobState _majorBlob;
  late DateTime _startTime;
  double _blobFadeOut = 1.0;
  DateTime? _hideStartTime;

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
      _blobFadeOut = 1.0;
      _ticker.repeat();
    } else {
      _blobFadeOut = 0.0;
    }
  }

  @override
  void didUpdateWidget(_BigMuteButton old) {
    super.didUpdateWidget(old);
    if (widget.state != old.state) {
      if (widget.state == MuteButtonState.unmuted && !_ticker.isAnimating) {
        _startTime = DateTime.now();
        _blobFadeOut = 1.0;
        _hideStartTime = null;
        _ticker.repeat();
      } else if (widget.state != MuteButtonState.unmuted &&
          old.state == MuteButtonState.unmuted) {
        _hideStartTime = DateTime.now();
        if (!_ticker.isAnimating) _ticker.repeat();
      }
      setState(() {});
    }
  }

  void _onTick() {
    _minorBlob.advance();
    _majorBlob.advance();
    if (_hideStartTime != null) {
      final elapsed = DateTime.now().difference(_hideStartTime!);
      _blobFadeOut = (1.0 - elapsed.inMilliseconds / _hideBlobsDuration.inMilliseconds).clamp(0.0, 1.0);
      if (_blobFadeOut <= 0.0) {
        _hideStartTime = null;
        _ticker.stop();
      }
    }
    setState(() {});
  }

  double get _pulseLevel {
    if (widget.state != MuteButtonState.unmuted && _blobFadeOut <= 0.0) return 0.0;
    final elapsed =
        DateTime.now().difference(_startTime).inMilliseconds;
    return 0.35 + 0.35 * math.sin(elapsed * 2 * math.pi / _pulsePeriodMs);
  }

  Color get _stateColor {
    if (_isScheduled) {
      return widget.isCanManage ? _greenColor : _purpleColor;
    }
    switch (widget.state) {
      case MuteButtonState.connecting:
        return _grayColor;
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
    // The button is inert while the call instance is still connecting.
    if (widget.state == MuteButtonState.connecting) return;
    widget.onTap?.call();
  }

  bool get _isScheduled => widget.scheduleDate > 0;

  String get _label {
    if (_isScheduled) {
      if (widget.isCanManage) return 'Start Now';
      return widget.scheduleStartSubscribed ? 'Cancel Reminder' : 'Set Reminder';
    }
    switch (widget.state) {
      case MuteButtonState.connecting:
        return 'Connecting...';
      case MuteButtonState.unmuted:
        return 'Mute';
      case MuteButtonState.muted:
        return 'Unmute';
      case MuteButtonState.forceMuted:
        return 'Raise Hand';
    }
  }

  IconData get _icon {
    if (_isScheduled) {
      if (widget.isCanManage) return Icons.play_arrow;
      return widget.scheduleStartSubscribed ? Icons.notifications_active : Icons.notifications_outlined;
    }
    switch (widget.state) {
      case MuteButtonState.connecting:
        return Icons.mic_none;
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
    final level = _pulseLevel * _blobFadeOut;
    final showBlob = level > 0.001;

    const hitWidth = 68.0;
    const hitHeight = 79.0;

    return GestureDetector(
      onTap: () => _handleTap(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RepaintBoundary(
            child: SizedBox(
              width: hitWidth,
              height: hitHeight,
              child: Stack(
                clipBehavior: Clip.none,
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
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 68,
        height: 79,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(color: Color(0xAAFFFFFF), fontSize: 11),
            ),
          ],
        ),
      ),
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
      child: SizedBox(
        width: 68,
        height: 79,
        child: Center(
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
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
  final engine = context.read<EngineService>();
  final appState = context.read<AppState>();
  final accountId = appState.activeAccountId;
  final selfUserId = appState.activeAccount?.selfUserId ?? '';
  final chatId = info.chatId;
  // Ephemeral group-call messages only (NOT permanent chat history). Sends go
  // through phone.sendGroupCallMessage and are echoed here locally.
  final callMessages = <CachedMessage>[];
  StateSetter? persistedSetState;

  // Mutable call state, kept live so the panel reacts to server-pushed changes
  // (admin force-mute/unmute) the same way AyuGram's setupRealMuteButtonState
  // binds the button to `_call->mutedValue()`.
  var selfMuted = isSelfMuted;
  var forceMuted = isForceMuted;
  var raisedHand = isRaisedHand;
  var cameraEnabled = false;
  var screenShareEnabled = false;
  var recording = isRecording;
  var messagesVisible = false;
  var pttActive = false;
  var scheduleSubscribed = info.scheduleStartSubscribed;
  // Show gray "Connecting…" until the call instance reports in, unless we're
  // already in the participant list (panel reopened on a live call) or scheduled.
  var connecting = info.scheduleDate == 0 &&
      !info.participants.any((p) => p.userId == selfUserId);

  // Seed the scheduled "Set/Cancel Reminder" toggle from real server state.
  if (info.scheduleDate > 0 && chatId.isNotEmpty) {
    engine.getGroupCallScheduleSubscribed(accountId, chatId).then((sub) {
      scheduleSubscribed = sub;
      persistedSetState?.call(() {});
    });
  }

  // Fallback: never get stuck on "Connecting…" if no state event arrives.
  final connectTimer = connecting
      ? Timer(const Duration(milliseconds: 1500), () {
          connecting = false;
          persistedSetState?.call(() {});
        })
      : null;

  final stateSub = engine.onGroupCallState.listen((event) {
    if (event.info.callId != info.callId) return;
    if (connecting) connecting = false; // receiving updates = connected
    GroupCallParticipant? self;
    for (final p in event.info.participants) {
      if (p.userId == selfUserId) {
        self = p;
        break;
      }
    }
    if (self != null) {
      // muted + can't self-unmute → admin force-muted (RaisedHand if hand up).
      forceMuted = self.isMuted && !self.canSelfUnmute && self.raisedHandRating == 0;
      raisedHand = self.isMuted && !self.canSelfUnmute && self.raisedHandRating > 0;
      selfMuted = self.isMuted && self.canSelfUnmute;
    }
    persistedSetState?.call(() {});
  });

  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (ctx) {
      final mq = MediaQuery.of(ctx);
      final screenW = mq.size.width;
      final screenH = mq.size.height;
      final panelWidth = info.isRtmp ? GroupCallPanel.defaultWidthRtmp : GroupCallPanel.defaultWidthNarrow;
      final panelHeight = info.isRtmp ? GroupCallPanel.defaultHeightRtmp : GroupCallPanel.defaultHeight;
      final w = math.min(panelWidth, screenW - 32);
      final h = math.min(panelHeight, screenH - 32);
      return Center(
        child: SizedBox(
          width: w,
          height: h,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: StatefulBuilder(
              builder: (sbCtx, setSbState) {
                persistedSetState = setSbState;
                return KeyboardListener(
                  focusNode: FocusNode()..requestFocus(),
                  autofocus: true,
                  onKeyEvent: (event) {
                    if (!info.isRtmp) return;
                    if (event.logicalKey == LogicalKeyboardKey.space) {
                      final engine = sbCtx.read<EngineService>();
                      final accountId = sbCtx.read<AppState>().activeAccountId;
                      final callId = info.callId;
                      if (callId.isEmpty) return;
                      if (event is KeyDownEvent && !pttActive) {
                        pttActive = true;
                        engine.setCallMuted(accountId, callId, false);
                      } else if (event is KeyUpEvent && pttActive) {
                        pttActive = false;
                        engine.setCallMuted(accountId, callId, true);
                      }
                    }
                  },
                  child: GroupCallPanel(
                  info: info,
                  chatTitle: chatTitle,
                  isRecording: recording,
                  isSelfMuted: selfMuted,
                  isForceMuted: forceMuted,
                  isRaisedHand: raisedHand,
                  isCanManage: isCanManage,
                  isConnecting: connecting,
                  isVideoActive: cameraEnabled,
                  isScreenShareActive: screenShareEnabled,
                  isMessagesVisible: messagesVisible,
                  scheduleDate: info.scheduleDate,
                  scheduleStartSubscribed: scheduleSubscribed,
                  callStartTime: callStartTime,
                  videoViewport: videoViewport,
                  onLeave: () {
                    if (isCanManage) {
                      _showLeaveOrEndDialog(ctx,
                        onLeave: () {
                          // A manager who picks "Leave" must still disconnect
                          // from the backend (AyuGram endCall()→hangup()).
                          final engine = sbCtx.read<EngineService>();
                          final accountId = sbCtx.read<AppState>().activeAccountId;
                          final callId = info.callId;
                          if (callId.isNotEmpty) {
                            engine.leaveGroupCall(accountId, callId);
                          }
                          Navigator.of(ctx).pop();
                        },
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
                      final engine = sbCtx.read<EngineService>();
                      final accountId = sbCtx.read<AppState>().activeAccountId;
                      final callId = info.callId;
                      if (callId.isNotEmpty) {
                        engine.leaveGroupCall(accountId, callId);
                      }
                      Navigator.of(ctx).pop();
                    }
                  },
                  onToggleMute: () {
                    final engine = sbCtx.read<EngineService>();
                    final accountId = sbCtx.read<AppState>().activeAccountId;
                    final callId = info.callId;
                    if (info.scheduleDate > 0) {
                      if (isCanManage) {
                        final scheduleTime = DateTime.fromMillisecondsSinceEpoch(info.scheduleDate * 1000);
                        final secsUntil = scheduleTime.difference(DateTime.now()).inSeconds;
                        if (secsUntil <= 10) {
                          if (callId.isNotEmpty) {
                            engine.startScheduledGroupCall(accountId, callId);
                          }
                        } else {
                          showDialog(
                            context: sbCtx,
                            builder: (dCtx) => AlertDialog(
                              backgroundColor: const Color(0xFF1E2530),
                              title: const Text('Start Now?', style: TextStyle(color: Colors.white)),
                              content: const Text('Are you sure you want to start this scheduled voice chat now?',
                                style: TextStyle(color: Color(0xAAFFFFFF))),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(dCtx).pop(),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(dCtx).pop();
                                    if (callId.isNotEmpty) {
                                      engine.startScheduledGroupCall(accountId, callId);
                                    }
                                  },
                                  child: const Text('Start'),
                                ),
                              ],
                            ),
                          );
                        }
                      } else {
                        final newSubscribed = !scheduleSubscribed;
                        setSbState(() => scheduleSubscribed = newSubscribed);
                        if (callId.isNotEmpty) {
                          engine.toggleGroupCallStartSubscription(accountId, callId, newSubscribed);
                        }
                      }
                      return;
                    }
                    if (forceMuted && raisedHand) {
                      setSbState(() => raisedHand = false);
                      if (callId.isNotEmpty) {
                        engine.raiseHand(accountId, callId, false);
                      }
                    } else if (forceMuted && !raisedHand) {
                      setSbState(() => raisedHand = true);
                      if (callId.isNotEmpty) {
                        engine.raiseHand(accountId, callId, true);
                      }
                    } else if (!forceMuted) {
                      setSbState(() => selfMuted = !selfMuted);
                      if (callId.isNotEmpty) {
                        engine.setCallMuted(accountId, callId, selfMuted);
                      }
                    }
                    onToggleMute?.call();
                  },
                  onToggleVideo: () {
                    final engine = sbCtx.read<EngineService>();
                    final accountId = sbCtx.read<AppState>().activeAccountId;
                    final callId = info.callId;
                    if (callId.isEmpty) return;
                    cameraEnabled = !cameraEnabled;
                    setSbState(() {});
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
                        screenShareEnabled = !screenShareEnabled;
                        setSbState(() {});
                        await engine.toggleScreenSharing(accountId, callId, screenShareEnabled,
                            sourceId: result.source.id, withAudio: result.withAudio);
                      }
                    }
                  },
                  onOpenMenu: () {
                    _showGroupCallMenu(ctx, callId: info.callId, chatId: info.chatId,
                      isRecording: recording,
                      onRecordingChanged: (v) {
                        recording = v;
                        setSbState(() {});
                      },
                    );
                  },
                  onToggleMessages: () {
                    messagesVisible = !messagesVisible;
                    setSbState(() {});
                  },
                  onSendMessage: (text) {
                    final engine = sbCtx.read<EngineService>();
                    final accountId = sbCtx.read<AppState>().activeAccountId;
                    final chatId = info.chatId;
                    if (chatId.isEmpty) return;
                    // Ephemeral group-call message (phone.sendGroupCallMessage),
                    // NOT a permanent chat message. Echo it locally for feedback.
                    engine.sendGroupCallMessage(accountId, chatId, text);
                    callMessages.add(CachedMessage(
                      accountId: accountId,
                      chatId: chatId,
                      msgId: 'gc_${DateTime.now().microsecondsSinceEpoch}',
                      senderId: selfUserId,
                      senderName: appState.activeAccount?.displayName ?? '',
                      contentText: text,
                      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                      isOutgoing: true,
                    ));
                    setSbState(() {});
                  },
                  callMessages: callMessages,
                ));
              },
            ),
          ),
        ),
      );
    },
  ).then((_) {
    stateSub.cancel();
    connectTimer?.cancel();
  });
}

void _showGroupCallMenu(BuildContext context, {String callId = '', String chatId = '', bool isRecording = false, ValueChanged<bool>? onRecordingChanged}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1E2530),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) {
      var recording = isRecording;
      return StatefulBuilder(
        builder: (ctx2, setSheetState) {
          final appState = ctx2.read<AppState>();
          final engine = context.read<EngineService>();
          final accountId = appState.activeAccountId;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline, color: Colors.white70),
                  title: const Text('Join As...',
                      style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(ctx2);
                    _showJoinAsChooser(context, chatId: chatId, callId: callId);
                  },
                ),
                ListTile(
                  leading: Icon(
                    recording ? Icons.stop_circle : Icons.fiber_manual_record,
                    color: Colors.redAccent,
                  ),
                  title: Text(
                    recording ? 'Stop Recording' : 'Start Recording',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx2);
                    if (callId.isNotEmpty) {
                      if (recording) {
                        await engine.stopCallRecording(accountId, callId);
                        recording = false;
                        onRecordingChanged?.call(false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Recording saved')),
                          );
                        }
                      } else {
                        final timestamp = DateTime.now().millisecondsSinceEpoch;
                        final tmpDir = await getTemporaryDirectory();
                        final filePath = '${tmpDir.path}/call_recording_$timestamp.wav';
                        await engine.startCallRecording(accountId, callId, filePath);
                        recording = true;
                        onRecordingChanged?.call(true);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Recording started')),
                          );
                        }
                      }
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.screen_share, color: Colors.white70),
                  title: const Text('Share Screen',
                      style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(ctx2);
                    final result = await showScreenShareChooser(context);
                    if (result != null && context.mounted) {
                      if (callId.isNotEmpty) {
                        await engine.toggleScreenSharing(accountId, callId, true,
                            sourceId: result.source.id, withAudio: result.withAudio);
                      }
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.person_add, color: Colors.white70),
                  title: const Text('Invite Members',
                      style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(ctx2);
                    _showInviteMembersFromMenu(context, callId: callId);
                  },
                ),
                ListTile(
                  leading:
                      const Icon(Icons.settings, color: Colors.white70),
                  title: const Text('Settings',
                      style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(ctx2);
                    _showCallSettingsFromMenu(context, callId: callId);
                  },
                ),
                const Divider(color: Color(0xFF2C3640), height: 1),
                ListTile(
                  leading: const Icon(Icons.call_end, color: Colors.redAccent),
                  title: const Text('Leave Call',
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(ctx2);
                    if (callId.isNotEmpty) {
                      engine.leaveGroupCall(accountId, callId);
                    }
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

// Lists the join-as *peer identities* (yourself / channels you manage) for THIS
// session — matching Telegram/AyuGram's phone.getGroupCallJoinAs — not local
// accounts. Selecting one rejoins the call under that identity.
Future<void> _showJoinAsChooser(BuildContext context, {String chatId = '', String callId = ''}) async {
  final engine = context.read<EngineService>();
  final accountId = context.read<AppState>().activeAccountId;
  if (chatId.isEmpty) return;

  final peers = await engine.getGroupCallJoinAsPeers(accountId, chatId);
  if (!context.mounted || peers.isEmpty) return;

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
              child: Text('Join As',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
            ...peers.map((peer) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: peer.isChannel
                        ? const Color(0xFF8774E1)
                        : const Color(0xFF3390EC),
                    radius: 18,
                    child: Icon(
                      peer.isChannel ? Icons.campaign : Icons.person,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  title: Text(peer.title.isNotEmpty ? peer.title : 'Unknown',
                      style: const TextStyle(color: Colors.white)),
                  subtitle: peer.subtitle.isNotEmpty
                      ? Text(peer.subtitle,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12))
                      : null,
                  trailing: peer.isSelf
                      ? const Icon(Icons.check_circle, color: Color(0xFF3390EC))
                      : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (peer.id.isEmpty) return;
                    // Rejoin under the chosen identity: leave, then join-as.
                    if (callId.isNotEmpty) {
                      await engine.leaveGroupCall(accountId, callId);
                    }
                    await engine.joinGroupCallAs(accountId, chatId, peer.id);
                  },
                )),
          ],
        ),
      );
    },
  );
}

Future<void> _showSoundDevicePicker(BuildContext context) async {
  final appState = context.read<AppState>();
  // Map from display name to raw device ID passed to engine
  final deviceMap = <String, String>{'Default': 'Default'};
  if (Platform.isLinux) {
    try {
      final result = await Process.run('pactl', ['list', 'sinks', 'short']);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).trim().split('\n');
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          final parts = line.split('\t');
          if (parts.length >= 2) {
            final rawName = parts[1];
            final displayName = rawName
                .replaceAll('alsa_output.', '')
                .replaceAll('.analog-stereo', ' (Analog Stereo)')
                .replaceAll('.hdmi-stereo', ' (HDMI Stereo)')
                .replaceAll('_', ' ');
            deviceMap[displayName] = rawName;
          }
        }
      }
    } catch (e) {
      Debug.log('call_screen', 'final result = await Process.run(\'pactl\', [\'list\', \'sinks...: $e');
    }
  } else if (Platform.isMacOS || Platform.isWindows) {
    try {
      final engine = context.read<EngineService>();
      final accountId = appState.activeAccountId;
      final devList = await engine.getAudioDevices(accountId, 'output');
      for (final d in devList) {
        deviceMap[d] = d;
      }
    } catch (e) {
      Debug.log('call_screen', 'final engine = context.read<EngineService>(): $e');
    }
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
            for (final entry in deviceMap.entries)
              ListTile(
                leading: Icon(
                  entry.value == current ? Icons.check_circle : Icons.circle_outlined,
                  color: entry.value == current ? const Color(0xFF4DC920) : Colors.white38,
                  size: 20,
                ),
                title: Text(entry.key, style: const TextStyle(color: Colors.white)),
                onTap: () {
                  appState.setCallOutputDevice(entry.value);
                  final engine = context.read<EngineService>();
                  final accountId = appState.activeAccountId;
                  engine.setCallAudioDevice(accountId, 'output', entry.value);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      );
    },
  );
}

Future<void> _showInviteMembersFromMenu(BuildContext context, {String callId = ''}) async {
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

  if (callId.isNotEmpty) {
    await engine.inviteToConferenceCall(accountId, callId, selectedIds.toList());
  }
}

void _showCallSettingsFromMenu(BuildContext context, {String callId = ''}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1E2530),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) => _CallSettingsSheet(callId: callId),
  );
}

/// Group-call settings: noise suppression, microphone (input) picker + live
/// mic-test meter, output device, and push-to-talk configuration. Ports
/// AyuGram's `calls_group_settings.cpp` (microphone + LevelMeter + PTT).
class _CallSettingsSheet extends StatefulWidget {
  final String callId;
  const _CallSettingsSheet({this.callId = ''});

  @override
  State<_CallSettingsSheet> createState() => _CallSettingsSheetState();
}

class _CallSettingsSheetState extends State<_CallSettingsSheet> {
  Timer? _micTimer;
  double _micLevel = 0.0;
  bool _recordingShortcut = false;
  final _shortcutFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _micTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      if (!mounted) return;
      try {
        final engine = context.read<EngineService>();
        final accountId = context.read<AppState>().activeAccountId;
        final level = await engine.getCallSoundPeak(accountId, widget.callId);
        if (mounted && (level - _micLevel).abs() > 0.01) {
          setState(() => _micLevel = level);
        }
      } catch (e) {
        Debug.log('call_screen', 'final engine = context.read<EngineService>(): $e');
      }
    });
  }

  @override
  void dispose() {
    _micTimer?.cancel();
    _shortcutFocus.dispose();
    super.dispose();
  }

  static String _formatDelay(int ms) {
    if (ms < 1000) return '${ms}ms';
    return '${(ms / 1000).toStringAsFixed(2)}s';
  }

  KeyEventResult _onShortcutKey(FocusNode node, KeyEvent event) {
    if (!_recordingShortcut || event is! KeyDownEvent) {
      return _recordingShortcut ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final modifiers = <LogicalKeyboardKey>{
      LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight,
      LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight,
    };
    if (modifiers.contains(key)) return KeyEventResult.handled;

    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final mods = <String>[];
    if (pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight)) mods.add('Ctrl');
    if (pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight)) mods.add('Shift');
    if (pressed.contains(LogicalKeyboardKey.altLeft) ||
        pressed.contains(LogicalKeyboardKey.altRight)) mods.add('Alt');
    if (pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight)) mods.add('Meta');
    var label = key.keyLabel;
    if (key == LogicalKeyboardKey.space) label = 'Space';
    if (label.isEmpty) label = key.debugName ?? 'Key';
    final shortcut = [...mods, label].join('+');
    context.read<AppState>().setCallPttShortcut(shortcut);
    setState(() => _recordingShortcut = false);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return SafeArea(
      child: SingleChildScrollView(
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
                appState.setCallNoiseSuppression(v);
                final engine = context.read<EngineService>();
                engine.setNoiseSuppression(appState.activeAccountId, '', v);
              },
            ),
            ListTile(
              leading: const Icon(Icons.mic, color: Colors.white70),
              title: const Text('Microphone',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text(appState.callInputDevice,
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                _showInputDevicePicker(context);
              },
            ),
            // Live mic-test level meter (AyuGram Ui::LevelMeter).
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _MicLevelMeter(level: _micLevel),
            ),
            ListTile(
              leading: const Icon(Icons.volume_up, color: Colors.white70),
              title: const Text('Output Device',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text(appState.callOutputDevice,
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                _showSoundDevicePicker(context);
              },
            ),
            const Divider(color: Color(0xFF2C3640), height: 1),
            SwitchListTile(
              title: const Text('Push to Talk',
                  style: TextStyle(color: Colors.white)),
              value: appState.callPushToTalk,
              activeColor: const Color(0xFF4DC920),
              onChanged: (v) => appState.setCallPushToTalk(v),
            ),
            if (appState.callPushToTalk) ...[
              Focus(
                focusNode: _shortcutFocus,
                onKeyEvent: _onShortcutKey,
                child: ListTile(
                  leading: const Icon(Icons.keyboard, color: Colors.white70),
                  title: const Text('Shortcut',
                      style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    _recordingShortcut ? 'Recording…' : appState.callPttShortcut,
                    style: TextStyle(
                        color: _recordingShortcut
                            ? const Color(0xFF4DC920)
                            : Colors.white38,
                        fontSize: 12),
                  ),
                  onTap: () {
                    setState(() => _recordingShortcut = true);
                    _shortcutFocus.requestFocus();
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Delay: ${_formatDelay(appState.callPttDelay)}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                    Slider(
                      value: appState.callPttDelay.toDouble().clamp(0, 2000),
                      min: 0,
                      max: 2000,
                      divisions: 200,
                      activeColor: const Color(0xFF4DC920),
                      onChanged: (v) => appState.setCallPttDelay(v.round()),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Horizontal mic-test level meter — ported from AyuGram's `Ui::LevelMeter`.
class _MicLevelMeter extends StatelessWidget {
  final double level;
  const _MicLevelMeter({required this.level});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 6,
      child: CustomPaint(
        size: const Size(double.infinity, 6),
        painter: _MicLevelPainter(level: level.clamp(0.0, 1.0)),
      ),
    );
  }
}

class _MicLevelPainter extends CustomPainter {
  final double level;
  _MicLevelPainter({required this.level});

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final bg = Paint()..color = const Color(0x33FFFFFF);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius), bg);
    if (level > 0.001) {
      final fg = Paint()..color = const Color(0xFF4DC920);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Offset.zero & Size(size.width * level, size.height), radius),
        fg,
      );
    }
  }

  @override
  bool shouldRepaint(_MicLevelPainter old) => old.level != level;
}

/// Microphone (audio input) device picker — mirrors `_showSoundDevicePicker`
/// but for capture devices. Ports AyuGram's ChooseCaptureDeviceBox.
Future<void> _showInputDevicePicker(BuildContext context) async {
  final appState = context.read<AppState>();
  final deviceMap = <String, String>{'Default': 'Default'};
  if (Platform.isLinux) {
    try {
      final result = await Process.run('pactl', ['list', 'sources', 'short']);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).trim().split('\n');
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          final parts = line.split('\t');
          if (parts.length >= 2) {
            final rawName = parts[1];
            // Skip monitor sources — those are output loopbacks, not mics.
            if (rawName.endsWith('.monitor')) continue;
            final displayName = rawName
                .replaceAll('alsa_input.', '')
                .replaceAll('.analog-stereo', ' (Analog Stereo)')
                .replaceAll('.analog-mono', ' (Analog Mono)')
                .replaceAll('_', ' ');
            deviceMap[displayName] = rawName;
          }
        }
      }
    } catch (e) {
      Debug.log('call_screen', 'final result = await Process.run(\'pactl\', [\'list\', \'sourc...: $e');
    }
  } else if (Platform.isMacOS || Platform.isWindows) {
    try {
      final engine = context.read<EngineService>();
      final devList = await engine.getAudioDevices(appState.activeAccountId, 'input');
      for (final d in devList) {
        deviceMap[d] = d;
      }
    } catch (e) {
      Debug.log('call_screen', 'final engine = context.read<EngineService>(): $e');
    }
  }

  if (!context.mounted) return;
  final current = appState.callInputDevice;
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
              child: Text('Microphone',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
            for (final entry in deviceMap.entries)
              ListTile(
                leading: Icon(
                  entry.value == current
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  color: entry.value == current
                      ? const Color(0xFF4DC920)
                      : Colors.white38,
                  size: 20,
                ),
                title: Text(entry.key,
                    style: const TextStyle(color: Colors.white)),
                onTap: () {
                  appState.setCallInputDevice(entry.value);
                  final engine = context.read<EngineService>();
                  engine.setCallAudioDevice(
                      appState.activeAccountId, 'input', entry.value);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
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
  final String callId;
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
    this.callId = '',
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
      if (mounted && widget.callStartTime != null) {
        setState(() {
          _durationSeconds = DateTime.now().difference(widget.callStartTime!).inSeconds;
          if (_durationSeconds < 0) _durationSeconds = 0;
        });
      }
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

  // The audio-level blobs are painted in the bar's own state color (AyuGram
  // _groupBrush): green active, blue muted, purple force-muted — not hardcoded.
  Color get _blobColor {
    switch (_toState) {
      case _CallBarState.active:
        return const Color(0xFF0DCC39);
      case _CallBarState.muted:
        return const Color(0xFF0992EF);
      case _CallBarState.forceMuted:
        return const Color(0xFF7A6AF1);
      case _CallBarState.connecting:
        return const Color(0xFF8F8F8F);
    }
  }

  static List<Color> _gradientColors(_CallBarState state, bool isPersonal) {
    if (isPersonal) {
      // Personal (1:1) calls use a FLAT solid fill (AyuGram calls_top_bar.cpp:823):
      // callBarBg (= dialogsBgActive #419fd9, blue) active, callBarBgMuted
      // (#8f8f8f) when muted. Only group calls use a gradient.
      switch (state) {
        case _CallBarState.active:
          return [const Color(0xFF419FD9), const Color(0xFF419FD9)];
        case _CallBarState.muted:
        case _CallBarState.connecting:
        case _CallBarState.forceMuted:
          return [const Color(0xFF8F8F8F), const Color(0xFF8F8F8F)];
      }
    }
    switch (state) {
      case _CallBarState.active:
        return [const Color(0xFF0dcc39), const Color(0xFF0bb6bd)];
      case _CallBarState.muted:
        return [const Color(0xFF0992ef), const Color(0xFF16ccfb)];
      case _CallBarState.connecting:
        return [const Color(0xFF7F8A96), const Color(0xFF7F8A96)];
      case _CallBarState.forceMuted:
        return [const Color(0xFFc65493), const Color(0xFF7a6af1), const Color(0xFF5f95e8)];
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
                if (!isPersonal &&
                    widget.callStartTime != null &&
                    !widget.isConnecting) ...[
                  Text(
                    _formatDuration(_durationSeconds),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
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
                  callId: widget.callId,
                ),
                const SizedBox(width: 12),
              ],
            ),
          ],
        ),
      ),
    ),
    if (showBlobs)
      _LinearBlobsBar(level: widget.audioLevel, color: _blobColor),
    ],
    );
  }
}

class _LinearBlobsBar extends StatefulWidget {
  final double level;
  final Color color;

  const _LinearBlobsBar({this.level = 0.0, this.color = const Color(0xFF4DC920)});

  static const _height = 3.0;
  static const _blobCount = 3;
  static const _segments = [5, 7, 8];

  @override
  State<_LinearBlobsBar> createState() => _LinearBlobsBarState();
}

class _LinearBlobsBarState extends State<_LinearBlobsBar>
    with SingleTickerProviderStateMixin {
  static const _hideBlobsDuration = Duration(milliseconds: 500);

  late AnimationController _ticker;
  late List<List<double>> _blobRadii;
  late List<List<double>> _blobTargets;
  final _rng = math.Random(42);
  DateTime? _zeroLevelSince;
  bool _frozen = false;

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

  @override
  void didUpdateWidget(_LinearBlobsBar old) {
    super.didUpdateWidget(old);
    if (widget.level > 0.001 && _frozen) {
      _frozen = false;
      _zeroLevelSince = null;
      _ticker.repeat();
    }
  }

  void _onTick() {
    if (widget.level < 0.001) {
      _zeroLevelSince ??= DateTime.now();
      if (DateTime.now().difference(_zeroLevelSince!) >= _hideBlobsDuration) {
        _frozen = true;
        _ticker.stop();
        return;
      }
    } else {
      _zeroLevelSince = null;
    }
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
        color: widget.color,
      ),
    );
  }
}

class _LinearBlobsPainter extends CustomPainter {
  final List<List<double>> blobRadii;
  final double level;
  final Color color;

  _LinearBlobsPainter({required this.blobRadii, required this.level, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // Layered translucent fills of the bar's state color (AyuGram _groupBrush).
    final colors = [
      color.withAlpha(60),
      color.withAlpha(40),
      color.withAlpha(30),
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
  bool shouldRepaint(_LinearBlobsPainter old) => true;
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
      size: const Size(15, 12),
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
                image: ResizeImage(
                  FileImage(File(avatarPath)),
                  width: (size * 2).toInt(),
                  height: (size * 2).toInt(),
                ),
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
  final String callId;

  const _CallBarHangupButton({this.onTap, this.isCanManage = false, this.callId = ''});

  void _handleTap(BuildContext context) {
    if (isCanManage) {
      _showLeaveOrEndDialog(context,
        onLeave: () {
          final engine = context.read<EngineService>();
          final appState = context.read<AppState>();
          final accountId = appState.activeAccountId;
          if (accountId.isNotEmpty && callId.isNotEmpty) {
            engine.leaveGroupCall(accountId, callId);
          }
          onTap?.call();
        },
        onEndForAll: () async {
          final engine = context.read<EngineService>();
          final appState = context.read<AppState>();
          final accountId = appState.activeAccountId;
          if (accountId.isNotEmpty && callId.isNotEmpty) {
            await engine.endGroupCall(accountId, callId);
          }
          onTap?.call();
        },
      );
    } else {
      final engine = context.read<EngineService>();
      final appState = context.read<AppState>();
      final accountId = appState.activeAccountId;
      if (accountId.isNotEmpty && callId.isNotEmpty) {
        engine.leaveGroupCall(accountId, callId);
      }
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
