import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/audio_service.dart';
import '../state/chat_state.dart';
import '../theme/theme.dart';

/// Now-playing media-player bar — a port of AyuGram's
/// `Media::Player::Widget` (`media/player/media_player_widget.cpp`). It appears
/// at the top of the window whenever a voice message or music track is loaded
/// in [AudioService], and exposes the previously-unreachable playback settings:
/// the repeat toggle (None→One→All), the order toggle (Default→Reverse→Shuffle),
/// the playback-speed control, and the autoplay-next toggle. Repeat / order /
/// autoplay are music-only (AyuGram gates them on `Type::Song`); the speed
/// control adjusts `audioPlaybackSpeed` for songs and `voicePlaybackSpeed` for
/// voice/round-video messages, matching `LookupPlaybackSpeed`.
///
/// Layout follows `media_player.style`: `mediaPlayerHeight: 35px` plus a 1px
/// bottom line, a thin seek bar (`mediaPlayerPlayback`), and 30px icon buttons.
class MusicPlayerBar extends StatelessWidget {
  const MusicPlayerBar({super.key});

  static const double _barHeight = 36; // mediaPlayerHeight 35 + 1px line

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioService>();
    final hasTrack = audio.currentMsgId.isNotEmpty;
    // AnimatedSize collapses the bar to zero height when there is no track,
    // mirroring AyuGram's player slide-in/out.
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: hasTrack
          ? _PlayerBarContent(audio: audio)
          : const SizedBox(width: double.infinity, height: 0),
    );
  }
}

class _PlayerBarContent extends StatelessWidget {
  final AudioService audio;
  const _PlayerBarContent({required this.audio});

  static String _fmt(Duration d) {
    final total = d.inSeconds;
    final m = total ~/ 60;
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final palette = context.palette;
    final isSong = audio.currentIsSong;

    final activeFg = palette.mediaPlayerActiveFg;
    final inactiveFg = palette.mediaPlayerInactiveFg;

    final mainText = isSong
        ? (audio.currentTitle.isNotEmpty ? audio.currentTitle : 'Unknown Track')
        : (audio.currentPerformer.isNotEmpty
            ? audio.currentPerformer
            : 'Voice message');
    final subText = isSong
        ? (audio.currentPerformer.isNotEmpty
            ? audio.currentPerformer
            : 'Unknown Artist')
        : '';

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        final currentSpeed =
            isSong ? appState.audioPlaybackSpeed : appState.voicePlaybackSpeed;

        final controls = <Widget>[
          _IconBtn(
            icon: Icons.skip_previous,
            tooltip: 'Previous track',
            color: activeFg,
            onTap: audio.previous,
          ),
          _IconBtn(
            icon: audio.playing ? Icons.pause : Icons.play_arrow,
            tooltip: audio.playing ? 'Pause' : 'Play',
            color: activeFg,
            onTap: audio.togglePlayback,
          ),
          _IconBtn(
            icon: Icons.skip_next,
            tooltip: 'Next track',
            color: activeFg,
            onTap: audio.next,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _TitleArea(
              mainText: mainText,
              subText: subText,
              palette: palette,
              onTap: () {
                if (audio.currentMsgTimestamp > 0) {
                  context.read<ChatState>().jumpToMessage(
                        audio.currentMsgTimestamp,
                        highlightMsgId: audio.currentMsgId,
                      );
                }
              },
            ),
          ),
          const SizedBox(width: 4),
          if (wide)
            Text(
              '${_fmt(audio.position)} / ${_fmt(audio.duration)}',
              style: TextStyle(fontSize: 12, color: palette.windowSubTextFg),
            ),
          if (wide) const SizedBox(width: 4),
          // Repeat + order are music-only and only shown inline when there is
          // room; otherwise they live in the overflow menu.
          if (isSong && wide) ...[
            _repeatButton(appState, activeFg, inactiveFg),
            _orderButton(appState, activeFg, inactiveFg),
          ],
          _speedButton(context, appState, isSong, currentSpeed, activeFg),
          if (isSong) _moreButton(context, appState, compact: !wide),
          _IconBtn(
            icon: Icons.close,
            tooltip: 'Close',
            color: palette.menuIconFg,
            onTap: audio.stop,
          ),
        ];

        return Material(
          color: palette.mediaPlayerBg,
          child: SizedBox(
            height: MusicPlayerBar._barHeight,
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(children: controls),
                  ),
                ),
                _SeekBar(
                  progress: audio.progress,
                  activeFg: activeFg,
                  inactiveFg: palette.mediaPlayerDisabledFg,
                  onSeek: audio.seek,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _repeatButton(AppState appState, Color active, Color inactive) {
    final mode = appState.playerRepeatMode; // 0=none,1=one,2=all
    final IconData icon = mode == 1 ? Icons.repeat_one : Icons.repeat;
    final tooltip = switch (mode) {
      1 => 'Repeat: one',
      2 => 'Repeat: all',
      _ => 'Repeat: off',
    };
    return _IconBtn(
      icon: icon,
      tooltip: tooltip,
      color: mode == 0 ? inactive : active,
      onTap: () => appState.setPlayerRepeatMode((mode + 1) % 3),
    );
  }

  Widget _orderButton(AppState appState, Color active, Color inactive) {
    final mode = appState.playerOrderMode; // 0=default,1=reverse,2=shuffle
    final IconData icon = switch (mode) {
      1 => Icons.swap_vert,
      2 => Icons.shuffle,
      _ => Icons.playlist_play,
    };
    final tooltip = switch (mode) {
      1 => 'Order: reverse',
      2 => 'Order: shuffle',
      _ => 'Order: in order',
    };
    return _IconBtn(
      icon: icon,
      tooltip: tooltip,
      color: mode == 0 ? inactive : active,
      onTap: () => appState.setPlayerOrderMode((mode + 1) % 3),
    );
  }

  Widget _speedButton(BuildContext context, AppState appState, bool isSong,
      double speed, Color active) {
    final palette = context.palette;
    final isDefault = (speed - 1.0).abs() < 0.01;
    String label(double v) =>
        v == v.roundToDouble() ? '${v.toInt()}×' : '$v×';
    return PopupMenuButton<double>(
      tooltip: 'Playback speed',
      initialValue: speed,
      position: PopupMenuPosition.under,
      onSelected: (v) => isSong
          ? appState.setAudioPlaybackSpeed(v)
          : appState.setVoicePlaybackSpeed(v),
      itemBuilder: (_) => [
        for (final v in const [0.5, 1.0, 1.5, 2.0])
          CheckedPopupMenuItem<double>(
            value: v,
            checked: (speed - v).abs() < 0.01,
            child: Text(label(v)),
          ),
      ],
      child: SizedBox(
        width: 40,
        height: 30,
        child: Center(
          child: Text(
            label(speed),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDefault ? palette.menuIconFg : active,
            ),
          ),
        ),
      ),
    );
  }

  Widget _moreButton(BuildContext context, AppState appState,
      {required bool compact}) {
    final palette = context.palette;
    return PopupMenuButton<String>(
      tooltip: 'More',
      position: PopupMenuPosition.under,
      icon: Icon(Icons.more_vert, size: 20, color: palette.menuIconFg),
      padding: EdgeInsets.zero,
      splashRadius: 18,
      onSelected: (value) {
        if (value == 'autoplay') {
          appState.setDisableAutoplayNext(!appState.disableAutoplayNext);
        } else if (value.startsWith('repeat:')) {
          appState.setPlayerRepeatMode(int.parse(value.substring(7)));
        } else if (value.startsWith('order:')) {
          appState.setPlayerOrderMode(int.parse(value.substring(6)));
        }
      },
      itemBuilder: (_) {
        final items = <PopupMenuEntry<String>>[];
        if (compact) {
          // Repeat / order didn't fit inline — offer them here.
          const repeatLabels = ['Repeat: off', 'Repeat: one', 'Repeat: all'];
          for (var i = 0; i < repeatLabels.length; i++) {
            items.add(CheckedPopupMenuItem<String>(
              value: 'repeat:$i',
              checked: appState.playerRepeatMode == i,
              child: Text(repeatLabels[i]),
            ));
          }
          items.add(const PopupMenuDivider());
          const orderLabels = [
            'Order: in order',
            'Order: reverse',
            'Order: shuffle'
          ];
          for (var i = 0; i < orderLabels.length; i++) {
            items.add(CheckedPopupMenuItem<String>(
              value: 'order:$i',
              checked: appState.playerOrderMode == i,
              child: Text(orderLabels[i]),
            ));
          }
          items.add(const PopupMenuDivider());
        }
        items.add(CheckedPopupMenuItem<String>(
          value: 'autoplay',
          checked: !appState.disableAutoplayNext,
          child: const Text('Autoplay next track'),
        ));
        return items;
      },
    );
  }
}

/// Track title + performer, single-line, tappable to jump to the message.
class _TitleArea extends StatelessWidget {
  final String mainText;
  final String subText;
  final TelegramPalette palette;
  final VoidCallback onTap;

  const _TitleArea({
    required this.mainText,
    required this.subText,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                mainText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.windowFg,
                ),
              ),
            ),
            if (subText.isNotEmpty) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  subText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.windowSubTextFg,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A 30×30 icon button matching the player's `mediaPlayerRepeatButton` sizing.
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        child: SizedBox(
          width: 32,
          height: 30,
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}

/// Thin seek bar at the bottom of the player (port of `mediaPlayerPlayback`,
/// a `FilledSlider`: 2px line, active/inactive colours). Tap or drag to seek.
class _SeekBar extends StatelessWidget {
  final double progress; // 0..1
  final Color activeFg;
  final Color inactiveFg;
  final Future<void> Function(double fraction) onSeek;

  const _SeekBar({
    required this.progress,
    required this.activeFg,
    required this.inactiveFg,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void seekAt(double dx) {
          if (width <= 0) return;
          onSeek((dx / width).clamp(0.0, 1.0));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seekAt(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
          child: SizedBox(
            height: 6,
            width: double.infinity,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: 2,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: inactiveFg)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: p,
                      child: ColoredBox(color: activeFg),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
