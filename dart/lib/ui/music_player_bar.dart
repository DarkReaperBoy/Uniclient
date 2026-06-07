import 'dart:async';

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/audio_service.dart';
import '../state/chat_state.dart';
import '../theme/theme.dart';

// ── Speed constants (ports of AyuGram media/media_common.h:41-43 and the
// sticky / preset tables in media/player/media_player_dropdown.cpp). ──
const double _kSpeedMin = 0.5; // kSpeedMin
const double _kSpeedMax = 2.5; // kSpeedMax
const double _kSpedUpDefault = 1.7; // kSpedUpDefault — restored on toggle from 1.0
const double _kSpeedSnap = 0.05; // sticky radius (media_player_dropdown.cpp:39-48)
const List<double> _kSpeedSticky = [0.8, 1.0, 1.2, 1.5, 1.7, 2.0, 2.2];
// Preset speed points (media_player_dropdown.cpp:215-246). Labels match
// lng_voice_speed_* (lang.strings:7235-7240).
const List<(double, String)> _kSpeedPresets = [
  (0.5, 'Slow'),
  (1.0, 'Normal'),
  (1.2, 'Medium'),
  (1.5, 'Fast'),
  (1.7, 'Very fast'),
  (2.0, 'Super fast'),
];

// mediaPlayerWideWidth (media_player.style:88): below this the entire
// right-controls group collapses and only reveals on hover.
const double _kWideWidth = 460;

/// EqualSpeeds (media_common.h:45-47): two speeds are equal if they round to the
/// same tenth.
bool _equalSpeeds(double a, double b) =>
    (a * 10).round() == (b * 10).round();

/// Formats a speed for the dropdown ("1.5×"); ports `number(value,'f',1)+'x'`.
String _fmtSpeed1(double v) => '${v.toStringAsFixed(1)}×';

/// Formats a speed compactly for the button ("1×" / "1.5×").
String _fmtSpeedShort(double v) =>
    v == v.roundToDouble() ? '${v.toInt()}×' : '$v×';

/// Now-playing media-player bar — a port of AyuGram's `Media::Player::Widget`
/// (`media/player/media_player_widget.cpp`). It appears at the top of the window
/// whenever a voice message or music track is loaded in [AudioService].
///
/// Left group: previous / play-pause / next. Middle: track name (tap jumps to
/// the message for voice or another-session songs). Right-controls group
/// (collapses below [_kWideWidth] and reveals on hover, matching AyuGram's
/// `_rightControls` FadeWrap toggled on `_over || !_narrow`): elapsed/total
/// time, the volume toggle + hover/wheel volume slider, the repeat toggle
/// (None→One→All), the order dropdown (Reverse / Shuffle), the playback-speed
/// dropdown (continuous 0.5×–2.5× slider + presets) and the autoplay menu.
/// A bottom seek bar (`mediaPlayerPlayback` FilledSlider: 4px at rest, growing
/// to 8px on hover over 150ms) tracks/scrubs playback.
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

class _PlayerBarContent extends StatefulWidget {
  final AudioService audio;
  const _PlayerBarContent({required this.audio});

  @override
  State<_PlayerBarContent> createState() => _PlayerBarContentState();
}

class _PlayerBarContentState extends State<_PlayerBarContent> {
  bool _hovering = false;

  static String _fmt(Duration d) {
    final total = d.inSeconds;
    final m = total ~/ 60;
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final audio = widget.audio;
    final appState = context.watch<AppState>();
    final palette = context.palette;
    final isSong = audio.currentIsSong;

    // AyuGram shows-the-item (jumps) only for voice messages or songs from a
    // different session/account; a current-session song instead toggles the
    // playlist dropdown (media_player_widget.cpp:482-514). The playlist dropdown
    // panel is a separate unported component, so for a current-session song the
    // name is non-interactive (default cursor, no jump).
    final fromAnotherSession = audio.currentAccountId.isNotEmpty &&
        appState.activeAccountId.isNotEmpty &&
        audio.currentAccountId != appState.activeAccountId;
    final canJump = !isSong || fromAnotherSession;

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
        final narrow = constraints.maxWidth < _kWideWidth;
        // _rightControls->toggle(_over || !_narrow) (widget.cpp:403-407).
        final showRight = !narrow || _hovering;

        // Right-controls group, in AyuGram right-to-left order: time, volume,
        // repeat (song only), order (song only), speed, then the autoplay menu.
        final rightControls = <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '${_fmt(audio.position)} / ${_fmt(audio.duration)}',
              style: TextStyle(fontSize: 12, color: palette.windowSubTextFg),
            ),
          ),
          _VolumeControl(appState: appState, activeFg: activeFg),
          if (isSong) _repeatButton(appState, activeFg, inactiveFg),
          if (isSong)
            _OrderButton(
                appState: appState, activeFg: activeFg, inactiveFg: inactiveFg),
          _SpeedControl(
              appState: appState,
              isSong: isSong,
              activeFg: activeFg,
              palette: palette),
          if (isSong) _moreButton(context, appState, palette),
        ];

        return Material(
          color: palette.mediaPlayerBg,
          child: MouseRegion(
            onEnter: (_) {
              if (!_hovering) setState(() => _hovering = true);
            },
            onExit: (_) {
              if (_hovering) setState(() => _hovering = false);
            },
            child: SizedBox(
              height: MusicPlayerBar._barHeight,
              child: Stack(
                children: [
                  // Controls live in the top 30px; the seek bar overlaps the
                  // bottom (mirroring AyuGram's playback slider over the content).
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8, right: 4, bottom: 6),
                      child: Row(
                        children: [
                          _IconBtn(
                            icon: Icons.skip_previous,
                            tooltip: 'Previous track',
                            color: activeFg,
                            onTap: audio.previous,
                          ),
                          _IconBtn(
                            icon: audio.playing
                                ? Icons.pause
                                : Icons.play_arrow,
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
                              canJump: canJump,
                              onTap: () {
                                if (canJump && audio.currentMsgTimestamp > 0) {
                                  context.read<ChatState>().jumpToMessage(
                                        audio.currentMsgTimestamp,
                                        highlightMsgId: audio.currentMsgId,
                                      );
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Narrow: the whole right group collapses and reveals
                          // on hover; wide: it is always shown.
                          AnimatedSize(
                            duration: const Duration(milliseconds: 150),
                            curve: Curves.easeOut,
                            alignment: Alignment.centerRight,
                            child: showRight
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: rightControls,
                                  )
                                : const SizedBox(height: 30),
                          ),
                          _IconBtn(
                            icon: Icons.close,
                            tooltip: 'Close',
                            color: palette.menuIconFg,
                            onTap: audio.stop,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _SeekBar(
                      progress: audio.progress,
                      activeFg: activeFg,
                      inactiveFg: inactiveFg,
                      onSeek: audio.seek,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Repeat toggle — None→One→All tap-cycle (widget.cpp:148-159).
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

  /// Autoplay-next menu. AyuGram's bar has no such control, but the
  /// `disableAutoplayNext` setting (OptionDisableAutoplayNext) has no other UI
  /// surface, so it is exposed here as a small overflow menu (song-only).
  Widget _moreButton(
      BuildContext context, AppState appState, TelegramPalette palette) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      position: PopupMenuPosition.under,
      icon: Icon(Icons.more_vert, size: 20, color: palette.menuIconFg),
      color: palette.menuBg,
      padding: EdgeInsets.zero,
      splashRadius: 18,
      onSelected: (value) {
        if (value == 'autoplay') {
          appState.setDisableAutoplayNext(!appState.disableAutoplayNext);
        }
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem<String>(
          value: 'autoplay',
          checked: !appState.disableAutoplayNext,
          child: const Text('Autoplay next track'),
        ),
      ],
    );
  }
}

/// Track title + performer, single-line. Tappable (pointer cursor) only when it
/// jumps — i.e. for voice messages or another-session songs (widget.cpp:507-512).
class _TitleArea extends StatelessWidget {
  final String mainText;
  final String subText;
  final TelegramPalette palette;
  final bool canJump;
  final VoidCallback onTap;

  const _TitleArea({
    required this.mainText,
    required this.subText,
    required this.palette,
    required this.canJump,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
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
    );

    if (!canJump) {
      // Current-session song: cursor stays default and the name is inert (the
      // playlist-dropdown toggle it would open is unported).
      return Align(alignment: Alignment.centerLeft, child: content);
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Align(alignment: Alignment.centerLeft, child: content),
    );
  }
}

/// A 32×30 icon button matching the player's `mediaPlayerRepeatButton` sizing.
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

// ───────────────────────────── Volume ─────────────────────────────

/// Volume toggle (mute / unmute) plus a hover- and wheel-driven vertical volume
/// slider dropdown — ports `_volumeToggle` + `PrepareVolumeDropdown`
/// (media_player_widget.cpp:57,130-141,202-216 +
/// media_player_volume_controller.cpp). The icon reflects 0 / <0.66 / full
/// volume (updateVolumeToggleIcon, widget.cpp:253-262).
class _VolumeControl extends StatelessWidget {
  final AppState appState;
  final Color activeFg;
  const _VolumeControl({required this.appState, required this.activeFg});

  IconData _icon(double v) => v <= 0
      ? Icons.volume_off
      : (v < 0.66 ? Icons.volume_down : Icons.volume_up);

  void _toggleMute() {
    // songVolume>0 → mute (0); else restore rememberedSongVolume (widget.cpp:130-137).
    final v = appState.songVolume > 0 ? 0.0 : appState.rememberedSongVolume;
    appState.setSongVolume(v);
  }

  void _onWheel(PointerScrollEvent e) {
    final next = (appState.songVolume - e.scrollDelta.dy / 1000.0).clamp(0.0, 1.0);
    if (next > 0) appState.setRememberedSongVolume(next);
    appState.setSongVolume(next);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final vol = appState.songVolume;
    return _HoverDropdown(
      width: 40,
      targetAnchor: Alignment.bottomCenter,
      followerAnchor: Alignment.topCenter,
      offset: const Offset(0, 2),
      panelBuilder: (context) => _VolumePanel(
        palette: palette,
        volume: vol,
        onChanged: (v) => appState.setSongVolume(v),
        onChangeEnd: (v) {
          if (v > 0) appState.setRememberedSongVolume(v);
          appState.setSongVolume(v);
        },
      ),
      child: Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) _onWheel(e);
        },
        child: _IconBtn(
          icon: _icon(vol),
          tooltip: 'Volume',
          color: activeFg,
          onTap: _toggleMute,
        ),
      ),
    );
  }
}

/// Vertical volume slider dropdown panel (mediaPlayerVolumeSize 27×100,
/// media_player.style:250).
class _VolumePanel extends StatelessWidget {
  final TelegramPalette palette;
  final double volume;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _VolumePanel({
    required this.palette,
    required this.volume,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.menuBg,
      elevation: 4,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: SizedBox(
          height: 100,
          child: _VerticalSlider(
            value: volume,
            activeColor: palette.mediaPlayerActiveFg,
            inactiveColor: palette.windowBgOver,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ),
    );
  }
}

class _VerticalSlider extends StatefulWidget {
  final double value; // 0..1, 0 at the bottom
  final Color activeColor;
  final Color inactiveColor;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _VerticalSlider({
    required this.value,
    required this.activeColor,
    required this.inactiveColor,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  State<_VerticalSlider> createState() => _VerticalSliderState();
}

class _VerticalSliderState extends State<_VerticalSlider> {
  double? _drag;

  void _apply(double dy, double h) {
    final v = (1 - dy / h).clamp(0.0, 1.0).toDouble();
    setState(() => _drag = v);
    widget.onChanged(v);
  }

  void _end() {
    widget.onChangeEnd(_drag ?? widget.value);
    setState(() => _drag = null);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _apply(d.localPosition.dy, h),
          onTapUp: (_) => _end(),
          onTapCancel: () => setState(() => _drag = null),
          onVerticalDragUpdate: (d) => _apply(d.localPosition.dy, h),
          onVerticalDragEnd: (_) => _end(),
          child: CustomPaint(
            size: Size.infinite,
            painter: _VerticalSliderPainter(
              value: _drag ?? widget.value,
              active: widget.activeColor,
              inactive: widget.inactiveColor,
            ),
          ),
        );
      },
    );
  }
}

class _VerticalSliderPainter extends CustomPainter {
  final double value;
  final Color active;
  final Color inactive;
  _VerticalSliderPainter(
      {required this.value, required this.active, required this.inactive});

  @override
  void paint(Canvas canvas, Size size) {
    const trackW = 6.0;
    final cx = size.width / 2;
    final left = cx - trackW / 2;
    final radius = const Radius.circular(trackW / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(left, 0, trackW, size.height), radius),
      Paint()..color = inactive,
    );
    final activeH = value * size.height;
    if (activeH > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(left, size.height - activeH, trackW, activeH), radius),
        Paint()..color = active,
      );
    }
    final my = (size.height - activeH).clamp(5.0, size.height - 5.0);
    canvas.drawCircle(Offset(cx, my), 5, Paint()..color = active);
  }

  @override
  bool shouldRepaint(_VerticalSliderPainter old) =>
      old.value != value || old.active != active || old.inactive != inactive;
}

// ───────────────────────────── Speed ─────────────────────────────

/// Playback-speed control. Hovering opens the speed dropdown (a continuous
/// 0.5×–2.5× slider with sticky points plus preset rows); a click toggles
/// default ⇄ last-non-default speed (media_player_dropdown.cpp:740-749). The
/// button label is coloured active when non-default.
class _SpeedControl extends StatefulWidget {
  final AppState appState;
  final bool isSong;
  final Color activeFg;
  final TelegramPalette palette;

  const _SpeedControl({
    required this.appState,
    required this.isSong,
    required this.activeFg,
    required this.palette,
  });

  @override
  State<_SpeedControl> createState() => _SpeedControlState();
}

class _SpeedControlState extends State<_SpeedControl> {
  double _lastNonDefault = _kSpedUpDefault;

  double get _speed => widget.isSong
      ? widget.appState.audioPlaybackSpeed
      : widget.appState.voicePlaybackSpeed;

  void _setSpeed(double v) {
    if (widget.isSong) {
      widget.appState.setAudioPlaybackSpeed(v);
    } else {
      widget.appState.setVoicePlaybackSpeed(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final speed = _speed;
    final isDefault = _equalSpeeds(speed, 1.0);
    if (!isDefault) _lastNonDefault = speed;

    return _HoverDropdown(
      width: 210,
      targetAnchor: Alignment.bottomRight,
      followerAnchor: Alignment.topRight,
      offset: const Offset(0, 2),
      panelBuilder: (context) => _SpeedPanel(
        palette: widget.palette,
        speed: speed,
        activeFg: widget.activeFg,
        onSpeed: _setSpeed,
      ),
      child: Tooltip(
        message: 'Playback speed',
        child: InkResponse(
          radius: 18,
          onTap: () {
            if (isDefault) {
              _setSpeed(
                  _equalSpeeds(_lastNonDefault, 1.0) ? _kSpedUpDefault : _lastNonDefault);
            } else {
              _setSpeed(1.0);
            }
          },
          child: SizedBox(
            width: 40,
            height: 30,
            child: Center(
              child: Text(
                _fmtSpeedShort(speed),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDefault ? widget.palette.menuIconFg : widget.activeFg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Speed dropdown panel: a sticky continuous slider on top, then the preset
/// speed rows (media_player_dropdown.cpp:176-284).
class _SpeedPanel extends StatelessWidget {
  final TelegramPalette palette;
  final double speed;
  final Color activeFg;
  final ValueChanged<double> onSpeed;

  const _SpeedPanel({
    required this.palette,
    required this.speed,
    required this.activeFg,
    required this.onSpeed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.menuBg,
      elevation: 4,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    _fmtSpeed1(speed),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.windowFg,
                    ),
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 24,
                    child: _SpeedSlider(
                      speed: speed,
                      onChanged: onSpeed,
                      activeColor: activeFg,
                      inactiveColor: palette.windowBgOver,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 9, thickness: 1, color: palette.windowBgOver),
          for (final preset in _kSpeedPresets)
            _SpeedPresetRow(
              palette: palette,
              speed: preset.$1,
              label: preset.$2,
              active: _equalSpeeds(preset.$1, speed),
              activeFg: activeFg,
              onTap: () => onSpeed(preset.$1),
            ),
        ],
      ),
    );
  }
}

class _SpeedPresetRow extends StatelessWidget {
  final TelegramPalette palette;
  final double speed;
  final String label;
  final bool active;
  final Color activeFg;
  final VoidCallback onTap;

  const _SpeedPresetRow({
    required this.palette,
    required this.speed,
    required this.label,
    required this.active,
    required this.activeFg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? activeFg : palette.windowFg;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(
                _fmtSpeed1(speed),
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 13, color: color)),
            ),
            if (active) Icon(Icons.check, size: 16, color: activeFg),
          ],
        ),
      ),
    );
  }
}

class _SpeedSlider extends StatefulWidget {
  final double speed;
  final ValueChanged<double> onChanged;
  final Color activeColor;
  final Color inactiveColor;

  const _SpeedSlider({
    required this.speed,
    required this.onChanged,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  State<_SpeedSlider> createState() => _SpeedSliderState();
}

class _SpeedSliderState extends State<_SpeedSlider> {
  double? _drag; // slider value 0..1 while dragging

  double _speedToSlider(double s) =>
      ((s - _kSpeedMin) / (_kSpeedMax - _kSpeedMin)).clamp(0.0, 1.0).toDouble();

  double _sliderToSpeed(double v) {
    final s = v * (_kSpeedMax - _kSpeedMin) + _kSpeedMin;
    return (s * 10).round() / 10;
  }

  /// setAdjustCallback sticky snapping (media_player_dropdown.cpp:164-173).
  double _snap(double s) {
    for (final p in _kSpeedSticky) {
      if (s > p - _kSpeedSnap && s < p + _kSpeedSnap) return p;
    }
    return s;
  }

  void _apply(double dx, double w) {
    final v = (dx / w).clamp(0.0, 1.0).toDouble();
    final speed = _snap(_sliderToSpeed(v));
    setState(() => _drag = _speedToSlider(speed));
    widget.onChanged(speed);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final value = _drag ?? _speedToSlider(widget.speed);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _apply(d.localPosition.dx, w),
          onTapUp: (_) => setState(() => _drag = null),
          onTapCancel: () => setState(() => _drag = null),
          onHorizontalDragUpdate: (d) => _apply(d.localPosition.dx, w),
          onHorizontalDragEnd: (_) => setState(() => _drag = null),
          child: CustomPaint(
            size: Size.infinite,
            painter: _HSliderPainter(
              value: value,
              active: widget.activeColor,
              inactive: widget.inactiveColor,
            ),
          ),
        );
      },
    );
  }
}

class _HSliderPainter extends CustomPainter {
  final double value;
  final Color active;
  final Color inactive;
  _HSliderPainter(
      {required this.value, required this.active, required this.inactive});

  @override
  void paint(Canvas canvas, Size size) {
    const trackH = 6.0;
    final cy = size.height / 2;
    final top = cy - trackH / 2;
    final radius = const Radius.circular(trackH / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, top, size.width, trackH), radius),
      Paint()..color = inactive,
    );
    final aw = value * size.width;
    if (aw > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, top, aw, trackH), radius),
        Paint()..color = active,
      );
    }
    final mx = (value * size.width).clamp(5.0, size.width - 5.0);
    canvas.drawCircle(Offset(mx, cy), 5, Paint()..color = active);
  }

  @override
  bool shouldRepaint(_HSliderPainter old) =>
      old.value != value || old.active != active || old.inactive != inactive;
}

// ───────────────────────────── Order ─────────────────────────────

/// Order button — opens a dropdown menu with two toggle actions, "Reverse
/// order" and "Shuffle"; clicking the active mode returns to Default
/// (media_player_dropdown.cpp:656-693). The icon reflects the active mode.
class _OrderButton extends StatelessWidget {
  final AppState appState;
  final Color activeFg;
  final Color inactiveFg;

  const _OrderButton({
    required this.appState,
    required this.activeFg,
    required this.inactiveFg,
  });

  @override
  Widget build(BuildContext context) {
    final mode = appState.playerOrderMode; // 0=default,1=reverse,2=shuffle
    final IconData icon = mode == 2 ? Icons.shuffle : Icons.swap_vert;
    final tooltip = switch (mode) {
      1 => 'Order: reverse',
      2 => 'Order: shuffle',
      _ => 'Playback order',
    };
    return _IconBtn(
      icon: icon,
      tooltip: tooltip,
      color: mode == 0 ? inactiveFg : activeFg,
      onTap: () => _show(context),
    );
  }

  void _show(BuildContext context) {
    final palette = context.palette;
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(box.size.bottomLeft(Offset.zero), ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final cur = appState.playerOrderMode;
    Widget item(int value, IconData icon, String label) {
      final on = cur == value;
      final fg = on ? palette.windowActiveTextFg : palette.windowFg;
      return Row(
        children: [
          Icon(icon, size: 18, color: on ? palette.windowActiveTextFg : palette.menuIconFg),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: fg)),
        ],
      );
    }

    showMenu<int>(
      context: context,
      position: position,
      color: palette.menuBg,
      items: [
        PopupMenuItem<int>(
            value: 1, child: item(1, Icons.swap_vert, 'Reverse order')),
        PopupMenuItem<int>(
            value: 2, child: item(2, Icons.shuffle, 'Shuffle')),
      ],
    ).then((value) {
      if (value == null) return;
      // Clicking the active mode returns to Default (dropdown.cpp:664-666).
      final next = (value == appState.playerOrderMode) ? 0 : value;
      appState.setPlayerOrderMode(next);
    });
  }
}

// ─────────────────────── Hover dropdown plumbing ───────────────────────

/// Wraps a button [child] and shows [panelBuilder]'s widget while the pointer is
/// over either the button or the panel — ports AyuGram's hover-driven dropdown
/// (WithDropdownController: enter shows the menu, leave hides it after a delay).
class _HoverDropdown extends StatefulWidget {
  final Widget child;
  final WidgetBuilder panelBuilder;
  final double width;
  final Alignment targetAnchor;
  final Alignment followerAnchor;
  final Offset offset;

  const _HoverDropdown({
    required this.child,
    required this.panelBuilder,
    required this.width,
    required this.targetAnchor,
    required this.followerAnchor,
    required this.offset,
  });

  @override
  State<_HoverDropdown> createState() => _HoverDropdownState();
}

class _HoverDropdownState extends State<_HoverDropdown> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();
  bool _overAnchor = false;
  bool _overPanel = false;
  Timer? _hideTimer;

  void _schedule() {
    _hideTimer?.cancel();
    if (_overAnchor || _overPanel) {
      if (!_controller.isShowing) _controller.show();
    } else {
      _hideTimer = Timer(const Duration(milliseconds: 200), () {
        if (!_overAnchor && !_overPanel && _controller.isShowing) {
          _controller.hide();
        }
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _controller,
      overlayChildBuilder: (context) {
        return Positioned(
          width: widget.width,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: widget.targetAnchor,
            followerAnchor: widget.followerAnchor,
            offset: widget.offset,
            child: MouseRegion(
              onEnter: (_) {
                _overPanel = true;
                _schedule();
              },
              onExit: (_) {
                _overPanel = false;
                _schedule();
              },
              child: widget.panelBuilder(context),
            ),
          ),
        );
      },
      child: CompositedTransformTarget(
        link: _link,
        child: MouseRegion(
          onEnter: (_) {
            _overAnchor = true;
            _schedule();
          },
          onExit: (_) {
            _overAnchor = false;
            _schedule();
          },
          child: widget.child,
        ),
      ),
    );
  }
}

// ───────────────────────────── Seek bar ─────────────────────────────

/// Bottom seek bar (port of `mediaPlayerPlayback` FilledSlider,
/// media_player.style:288-295 + continuous_sliders.cpp:219-252). The filled line
/// is 4px at rest and grows to 8px on hover over 150ms; the unfilled track only
/// appears on hover, fading in with the over factor. Tap or drag to seek.
class _SeekBar extends StatefulWidget {
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
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hover = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150), // mediaPlayerPlayback.duration
  );
  double? _dragValue;

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        double frac(double dx) =>
            width <= 0 ? 0.0 : (dx / width).clamp(0.0, 1.0).toDouble();
        return MouseRegion(
          onEnter: (_) => _hover.forward(),
          onExit: (_) => _hover.reverse(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) =>
                setState(() => _dragValue = frac(d.localPosition.dx)),
            onTapUp: (d) {
              final v = frac(d.localPosition.dx);
              widget.onSeek(v);
              setState(() => _dragValue = null);
            },
            onTapCancel: () => setState(() => _dragValue = null),
            onHorizontalDragUpdate: (d) =>
                setState(() => _dragValue = frac(d.localPosition.dx)),
            onHorizontalDragEnd: (_) {
              final v = _dragValue;
              if (v != null) widget.onSeek(v);
              setState(() => _dragValue = null);
            },
            child: SizedBox(
              height: 8, // fullWidth — the hover-grown thickness
              width: double.infinity,
              child: AnimatedBuilder(
                animation: _hover,
                builder: (context, _) => CustomPaint(
                  size: Size.infinite,
                  painter: _SeekPainter(
                    value: _dragValue ?? widget.progress.clamp(0.0, 1.0),
                    over: _hover.value,
                    activeFg: widget.activeFg,
                    inactiveFg: widget.inactiveFg,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SeekPainter extends CustomPainter {
  final double value; // 0..1
  final double over; // 0..1 hover factor
  final Color activeFg;
  final Color inactiveFg;

  static const double _lineWidth = 4; // resting thickness
  static const double _fullWidth = 8; // hover thickness

  _SeekPainter({
    required this.value,
    required this.over,
    required this.activeFg,
    required this.inactiveFg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // lineWidth = lineWidth + (fullWidth-lineWidth)*over (continuous_sliders.cpp:228).
    final lineWidth = _lineWidth + (_fullWidth - _lineWidth) * over;
    final top = size.height - lineWidth;
    final mid = (value * size.width).clamp(0.0, size.width);
    final paint = Paint();
    if (mid > 0) {
      paint.color = activeFg;
      canvas.drawRect(Rect.fromLTWH(0, top, mid, lineWidth), paint);
    }
    // The unfilled track only shows on hover, fading in with `over`.
    if (size.width > mid && over > 0) {
      paint.color = inactiveFg.withValues(alpha: over.clamp(0.0, 1.0));
      canvas.drawRect(
          Rect.fromLTWH(mid, top, size.width - mid, lineWidth), paint);
    }
  }

  @override
  bool shouldRepaint(_SeekPainter old) =>
      old.value != value ||
      old.over != over ||
      old.activeFg != activeFg ||
      old.inactiveFg != inactiveFg;
}
