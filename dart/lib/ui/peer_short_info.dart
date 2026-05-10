import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/chat_state.dart';
import 'popup_menu.dart';
import 'telegram_toast.dart';

const double _kBoxWidth = 304.0;
const double _kCoverSize = 304.0;
const double _kBoxRadius = 6.0;
const double _kShadowHeight = 80.0;
const double _kNameX = 25.0;
const double _kNameY = 37.0;
const double _kStatusX = 25.0;
const double _kStatusY = 14.0;
const double _kInfoPaddingH = 24.0;
const double _kInfoPaddingTop = 16.0;
const double _kScrollBarWidth = 8.0;
const Duration _kAnimDuration = Duration(milliseconds: 200);
const double _kBarHeight = 2.0;
const double _kBarPadding = 8.0;
const double _kBarGap = 4.0;
const double _kInactiveBarOpacity = 0.5;
const double _kShadowMaxAlpha = 80 / 255;
const double _kParallaxFactor = 0.3;
const Duration _kRadialFadeDelay = Duration(milliseconds: 300);
const double _kScrollBarInset = 3.0;
const Duration _kScrollShowDuration = Duration(milliseconds: 150);
const Duration _kScrollHideDelay = Duration(milliseconds: 1000);
const double _kBoxMarginTop = 48.0;
const double _kBoxMarginBottom = 32.0;

void showPeerShortInfoBox(
  BuildContext context, {
  required String accountId,
  required String peerId,
  required String peerName,
  required String avatarPath,
  required ChatType peerType,
  int memberCount = 0,
}) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'PeerShortInfo',
    barrierColor: Colors.transparent,
    transitionDuration: _kAnimDuration,
    transitionBuilder: (ctx, anim, secondaryAnim, child) {
      return Stack(
        children: [
          // Barrier: easeOutCirc curve per §38.3
          IgnorePointer(
            child: FadeTransition(
              opacity:
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCirc),
              child: const ColoredBox(
                color: Color(0x8A000000),
                child: SizedBox.expand(),
              ),
            ),
          ),
          // Box: linear opacity per §38.3
          FadeTransition(
            opacity: anim,
            child: child,
          ),
        ],
      );
    },
    pageBuilder: (ctx, anim, secondaryAnim) {
      return _PeerShortInfoBox(
        accountId: accountId,
        peerId: peerId,
        peerName: peerName,
        avatarPath: avatarPath,
        peerType: peerType,
        memberCount: memberCount,
      );
    },
  );
}

class _PeerShortInfoBox extends StatefulWidget {
  final String accountId;
  final String peerId;
  final String peerName;
  final String avatarPath;
  final ChatType peerType;
  final int memberCount;

  const _PeerShortInfoBox({
    required this.accountId,
    required this.peerId,
    required this.peerName,
    required this.avatarPath,
    required this.peerType,
    this.memberCount = 0,
  });

  @override
  State<_PeerShortInfoBox> createState() => _PeerShortInfoBoxState();
}

class _PeerShortInfoBoxState extends State<_PeerShortInfoBox> {
  UserProfile? _profile;
  bool _loadingProfile = false;
  int _photoCount = 1;
  int _currentPhotoIndex = 0;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollNotifier = ValueNotifier(0.0);
  final FocusNode _focusNode = FocusNode();
  bool _showRadialLoader = false;
  Player? _videoPlayer;
  VideoController? _videoController;
  String _statusText = '';
  int _liveMemberCount = 0;
  StreamSubscription<UserStatusEvent>? _statusSub;
  StreamSubscription<ChatInfo>? _chatUpdateSub;
  String? _currentPhotoPath;

  @override
  void initState() {
    super.initState();
    _liveMemberCount = widget.memberCount;
    _scrollController.addListener(_onScroll);
    _focusNode.requestFocus();
    _loadProfile();
    _subscribeToEvents();
    Future.delayed(_kRadialFadeDelay, () {
      if (mounted && _loadingProfile) {
        setState(() => _showRadialLoader = true);
      }
    });
  }

  void _subscribeToEvents() {
    final engine = context.read<EngineService>();
    if (_isDm) {
      _statusSub = engine.onUserStatus.listen((event) {
        if (event.userId == widget.peerId &&
            event.accountId == widget.accountId &&
            mounted) {
          setState(() {
            _statusText = _computeStatusFromEvent(event);
          });
        }
      });
    }
    _chatUpdateSub = engine.onChatUpdated.listen((chat) {
      if (chat.chatId == widget.peerId &&
          chat.accountId == widget.accountId &&
          mounted) {
        if (chat.memberCount > 0 && chat.memberCount != _liveMemberCount) {
          setState(() => _liveMemberCount = chat.memberCount);
        }
      }
    });
  }

  String _computeStatusFromEvent(UserStatusEvent event) {
    if (event.isOnline) return 'online';
    switch (event.lastSeenKind) {
      case 'online':
        return 'online';
      case 'recently':
        return 'last seen recently';
      case 'within_week':
        return 'last seen within a week';
      case 'within_month':
        return 'last seen within a month';
      case 'long_ago':
        return 'last seen a long time ago';
      case 'hidden':
        return 'last seen recently';
      case 'exact':
        if (event.lastSeenMs > 0) {
          final dt =
              DateTime.fromMillisecondsSinceEpoch(event.lastSeenMs);
          final now = DateTime.now();
          final diff = now.difference(dt);
          if (diff.inMinutes < 1) return 'last seen just now';
          if (diff.inMinutes < 60) {
            return 'last seen ${diff.inMinutes} min ago';
          }
          if (diff.inHours < 24) {
            return 'last seen ${diff.inHours}h ago';
          }
          final months = [
            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
          ];
          return 'last seen ${months[dt.month - 1]} ${dt.day}';
        }
        return 'last seen recently';
      default:
        return 'last seen recently';
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _chatUpdateSub?.cancel();
    _disposeVideoPlayer();
    _scrollController.dispose();
    _scrollNotifier.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _disposeVideoPlayer() {
    _videoPlayer?.dispose();
    _videoPlayer = null;
    _videoController = null;
  }

  void _initVideoIfAvailable() {
    if (_profile?.videoAvatarPath.isNotEmpty == true) {
      final player = Player();
      _videoPlayer = player;
      _videoController = VideoController(player);
      player.setPlaylistMode(PlaylistMode.loop);
      player.open(Media(_profile!.videoAvatarPath));
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset.clamp(0.0, double.infinity);
    _scrollNotifier.value = offset;
  }

  Future<void> _loadProfile() async {
    setState(() => _loadingProfile = true);
    try {
      final engine = context.read<EngineService>();
      final profile =
          await engine.getUserProfile(widget.accountId, widget.peerId);
      if (mounted) {
        setState(() {
          _profile = profile;
          _loadingProfile = false;
          _showRadialLoader = false;
          if (profile != null) {
            _statusText = _computeInitialStatus(profile);
          }
        });
        _initVideoIfAvailable();
        _fetchPhotoCount();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingProfile = false;
          _showRadialLoader = false;
        });
      }
    }
  }

  String _computeInitialStatus(UserProfile profile) {
    if (profile.isBot) return 'bot';
    if (profile.isOnline) return 'online';
    switch (profile.lastSeenKind) {
      case 'online':
        return 'online';
      case 'recently':
      case 'hidden':
        return 'last seen recently';
      case 'within_week':
        return 'last seen within a week';
      case 'within_month':
        return 'last seen within a month';
      case 'long_ago':
        return 'last seen a long time ago';
      case 'exact':
        if (profile.lastSeen > 0) {
          final dt = DateTime.fromMillisecondsSinceEpoch(profile.lastSeen);
          final now = DateTime.now();
          final diff = now.difference(dt);
          if (diff.inMinutes < 1) return 'last seen just now';
          if (diff.inMinutes < 60) {
            return 'last seen ${diff.inMinutes} min ago';
          }
          if (diff.inHours < 24) {
            return 'last seen ${diff.inHours}h ago';
          }
          final months = [
            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
          ];
          return 'last seen ${months[dt.month - 1]} ${dt.day}';
        }
        return 'last seen recently';
      default:
        return 'last seen recently';
    }
  }

  Future<void> _fetchPhotoCount() async {
    if (!_isDm) return;
    try {
      final engine = context.read<EngineService>();
      final count =
          await engine.getUserPhotoCount(widget.accountId, widget.peerId);
      if (mounted && count > 0) {
        setState(() => _photoCount = count);
      }
    } catch (_) {}
  }

  void _navigatePhoto(int delta) {
    if (_photoCount <= 1) return;
    final newIndex = (_currentPhotoIndex + delta) % _photoCount;
    final idx = newIndex < 0 ? newIndex + _photoCount : newIndex;
    setState(() {
      _currentPhotoIndex = idx;
      _currentPhotoPath = null;
    });
    _fetchPhotoAtIndex(idx);
  }

  Future<void> _fetchPhotoAtIndex(int index) async {
    if (index == 0) {
      setState(() => _currentPhotoPath = null);
      return;
    }
    try {
      final engine = context.read<EngineService>();
      final path = await engine.getUserPhotoAtIndex(
          widget.accountId, widget.peerId, index);
      if (mounted && _currentPhotoIndex == index && path != null) {
        setState(() => _currentPhotoPath = path);
      }
    } catch (_) {}
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final chatState = context.read<ChatState>();
    final isAlreadyOpen = chatState.activeChat?.chatId == widget.peerId &&
        chatState.activeChat?.accountId == widget.accountId;
    if (isAlreadyOpen) return;
    showTelegramMenu<String>(
      context: context,
      position: position,
      items: [
        TelegramMenuItem<String>(
          value: 'new_window',
          icon: const Icon(Icons.open_in_new, size: 20),
          label: 'Open in New Window',
        ),
      ],
    ).then((value) {
      if (value == 'new_window' && mounted) {
        Navigator.of(context).pop();
        final chat = chatState.chats
            .where((c) =>
                c.chatId == widget.peerId &&
                c.accountId == widget.accountId)
            .firstOrNull;
        if (chat != null) chatState.openChat(chat);
      }
    });
  }

  bool get _isDm => widget.peerType == ChatType.dm;
  bool get _isGroup => widget.peerType == ChatType.group;
  bool get _isChannel => widget.peerType == ChatType.channel;

  bool get _isSelf {
    try {
      final chatState = context.read<ChatState>();
      final chat = chatState.chats
          .where((c) =>
              c.chatId == widget.peerId &&
              c.accountId == widget.accountId)
          .firstOrNull;
      return chat?.isSelf ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenSize = MediaQuery.of(context).size;
    final maxHeight = screenSize.height - _kBoxMarginTop - _kBoxMarginBottom;
    final bgColor = isDark ? const Color(0xFF17212b) : Colors.white;

    return Center(
      child: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
          }
        },
        child: Material(
          type: MaterialType.transparency,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              if (event.buttons == 2) {
                _showContextMenu(context, event.position);
              }
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: _kBoxWidth,
                maxHeight: maxHeight,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_kBoxRadius),
                child: Container(
                  color: bgColor,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child:
                            _buildScrollableContent(theme, isDark, bgColor),
                      ),
                      _buildButtons(theme, isDark),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollableContent(
      ThemeData theme, bool isDark, Color bgColor) {
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        ValueListenableBuilder<double>(
          valueListenable: _scrollNotifier,
          builder: (context, scrollOffset, child) {
            return Positioned(
              top: -scrollOffset * _kParallaxFactor,
              left: 0,
              right: 0,
              height: _kCoverSize,
              child: child!,
            );
          },
          child: _buildCoverBackground(isDark),
        ),
        RawScrollbar(
          controller: _scrollController,
          thickness: _kScrollBarWidth,
          crossAxisMargin: _kScrollBarInset,
          fadeDuration: _kScrollShowDuration,
          timeToFade: _kScrollHideDelay,
          radius: const Radius.circular(4),
          thumbColor: isDark
              ? const Color(0x4DFFFFFF)
              : const Color(0x66C7C7C7),
          child: ListView(
            controller: _scrollController,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              _buildCoverOverlay(theme, isDark),
              Container(
                color: bgColor,
                child: _buildInfoRows(theme, isDark),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCoverBackground(bool isDark) {
    final photoPath = _currentPhotoPath ?? widget.avatarPath;
    final hasAvatar = photoPath.isNotEmpty;

    Widget staticImage;
    if (hasAvatar) {
      staticImage = Image.file(
        File(photoPath),
        key: ValueKey(photoPath),
        fit: BoxFit.cover,
        width: _kCoverSize,
        height: _kCoverSize,
        errorBuilder: (_, __, ___) => Container(color: Colors.black),
      );
    } else {
      final displayName = _profile?.displayName.isNotEmpty == true
          ? _profile!.displayName
          : widget.peerName;
      staticImage = Container(
        color: Colors.black,
        child: Center(
          child: Text(
            _initials(displayName),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 80,
              fontWeight: FontWeight.w300,
            ),
          ),
        ),
      );
    }

    if (_videoController != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          staticImage,
          Video(
            controller: _videoController!,
            width: _kCoverSize,
            height: _kCoverSize,
            fit: BoxFit.cover,
            controls: NoVideoControls,
          ),
        ],
      );
    }

    return staticImage;
  }

  String _computeAdditionalStatus() {
    if (!_isDm || _profile == null) return '';
    if (_currentPhotoIndex == 0 && _profile!.hasPersonalPhoto) {
      return 'Set by you';
    }
    if (_photoCount > 1 && _currentPhotoIndex == _photoCount - 1) {
      return 'Public photo';
    }
    return '';
  }

  Widget _buildCoverOverlay(ThemeData theme, bool isDark) {
    final displayName = _profile?.displayName.isNotEmpty == true
        ? _profile!.displayName
        : widget.peerName;

    String statusText;
    if (_isDm) {
      statusText = _statusText.isNotEmpty
          ? _statusText
          : (_profile?.isBot == true ? 'bot' : 'last seen recently');
    } else if (_isChannel) {
      statusText = _liveMemberCount > 0
          ? '${_formatCount(_liveMemberCount)} subscribers'
          : 'channel';
    } else {
      statusText = _liveMemberCount > 0
          ? '${_formatCount(_liveMemberCount)} members'
          : 'group';
    }

    final additionalStatus = _computeAdditionalStatus();

    final topBarAreaHeight = _kBarPadding * 2 + _kBarHeight;

    return SizedBox(
      width: _kCoverSize,
      height: _kCoverSize,
      child: ValueListenableBuilder<double>(
        valueListenable: _scrollNotifier,
        builder: (context, scrollOffset, _) {
          final fadeEnd = _kCoverSize - _kShadowHeight;
          double opacity;
          if (scrollOffset <= 0) {
            opacity = 1.0;
          } else if (scrollOffset >= fadeEnd) {
            opacity = 0.0;
          } else {
            opacity = (1.0 - scrollOffset / fadeEnd).clamp(0.0, 1.0);
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: topBarAreaHeight + 10,
                child: Opacity(
                  opacity: opacity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: _kShadowMaxAlpha),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _kShadowHeight,
                child: Opacity(
                  opacity: opacity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: _kShadowMaxAlpha),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_photoCount > 1)
                Positioned(
                  left: _kBarPadding,
                  right: _kBarPadding,
                  top: _kBarPadding,
                  height: _kBarHeight,
                  child: Opacity(
                    opacity: opacity,
                    child: CustomPaint(
                      painter: _PhotoProgressBarsPainter(
                        count: _photoCount,
                        activeIndex: _currentPhotoIndex,
                        barColor: Colors.white,
                        gap: _kBarGap,
                        inactiveOpacity: _kInactiveBarOpacity,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: _kNameX,
                right: _kNameX,
                bottom: _kNameY,
                child: Opacity(
                  opacity: opacity,
                  child: Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.27,
                    ),
                  ),
                ),
              ),
              if (additionalStatus.isNotEmpty)
                Positioned(
                  left: _kStatusX,
                  right: _kStatusX,
                  bottom: _kStatusY + 16,
                  child: Opacity(
                    opacity: opacity,
                    child: Text(
                      additionalStatus,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: _kStatusX,
                right: _kStatusX,
                bottom: _kStatusY,
                child: Opacity(
                  opacity: opacity,
                  child: Text(
                    statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              if (_photoCount > 1) ...[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: _kCoverSize / 3,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _navigatePhoto(-1),
                      behavior: HitTestBehavior.opaque,
                    ),
                  ),
                ),
                Positioned(
                  left: _kCoverSize / 3,
                  top: 0,
                  bottom: 0,
                  right: 0,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _navigatePhoto(1),
                      behavior: HitTestBehavior.opaque,
                    ),
                  ),
                ),
              ],
              if (_showRadialLoader)
                Positioned.fill(
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: 1.0,
                      duration: _kAnimDuration,
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoRows(ThemeData theme, bool isDark) {
    final labelColor =
        isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd);
    final valueColor = isDark ? Colors.white : Colors.black87;

    if (_loadingProfile && _profile == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_profile == null) return const SizedBox.shrink();
    final p = _profile!;
    final rows = <Widget>[];

    if (_isDm) {
      if (p.personalChannelName.isNotEmpty) {
        rows.add(_infoRow(
          label: 'Channel',
          value: p.personalChannelName,
          labelColor: labelColor,
          valueColor: valueColor,
          copyText: p.personalChannelName,
          copyLabel: 'Channel name copied',
          onTap: () {
            if (p.personalChannelId.isNotEmpty) {
              Navigator.of(context).pop();
              final chatState = context.read<ChatState>();
              final chat = chatState.chats
                  .where((c) =>
                      c.chatId == p.personalChannelId &&
                      c.accountId == widget.accountId)
                  .firstOrNull;
              if (chat != null) chatState.openChat(chat);
            }
          },
        ));
      }

      if (p.phone.isNotEmpty) {
        rows.add(_infoRow(
          label: 'Mobile',
          value: _formatPhone(p.phone),
          labelColor: labelColor,
          valueColor: valueColor,
          copyText: p.phone,
          copyLabel: 'Copy Phone Number',
        ));
      }

      if (p.bio.isNotEmpty) {
        rows.add(_infoRow(
          label: p.isBot ? 'About' : 'Bio',
          value: p.bio,
          labelColor: labelColor,
          valueColor: valueColor,
          multiLine: true,
          parseEntities: true,
        ));
      }

      if (p.username.isNotEmpty) {
        final usernameLink = 'https://t.me/${p.username}';
        rows.add(_infoRow(
          label: 'Username',
          value: '@${p.username}',
          labelColor: labelColor,
          valueColor: valueColor,
          copyText: '@${p.username}',
          copyLabel: 'Copy Mention',
          onTap: () => launchUrl(Uri.parse(usernameLink),
              mode: LaunchMode.externalApplication),
        ));
      }

      if (p.hasBirthday) {
        final isBirthdayToday =
            _isBirthdayToday(p.birthdayDay, p.birthdayMonth);
        rows.add(_infoRow(
          label: isBirthdayToday ? 'Birthday today' : 'Birthday',
          value: _formatBirthday(
              p.birthdayDay, p.birthdayMonth, p.birthdayYear),
          labelColor: labelColor,
          valueColor: valueColor,
        ));
      }

      if (p.notes.isNotEmpty) {
        rows.add(_infoRow(
          label: 'Notes',
          value: p.notes,
          labelColor: labelColor,
          valueColor: valueColor,
          multiLine: true,
          parseEntities: true,
        ));
      }
    } else {
      if (p.username.isNotEmpty) {
        final link = 'https://t.me/${p.username}';
        rows.add(_infoRow(
          label: 'Link',
          value: 't.me/${p.username}',
          labelColor: labelColor,
          valueColor: valueColor,
          copyText: link,
          copyLabel: 'Link copied',
          onTap: () => launchUrl(Uri.parse(link),
              mode: LaunchMode.externalApplication),
        ));
      }

      if (p.bio.isNotEmpty) {
        rows.add(_infoRow(
          label: 'About',
          value: p.bio,
          labelColor: labelColor,
          valueColor: valueColor,
          multiLine: true,
          parseEntities: true,
        ));
      }
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return AnimatedSize(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
    );
  }

  Widget _infoRow({
    required String label,
    required String value,
    required Color labelColor,
    required Color valueColor,
    bool multiLine = false,
    String? copyText,
    String? copyLabel,
    VoidCallback? onTap,
    bool parseEntities = false,
  }) {
    final displayValue =
        multiLine ? value : value.replaceAll(' ', ' ');

    Widget valueWidget;
    if (parseEntities) {
      valueWidget = SelectableText.rich(
        _parseTextWithEntities(displayValue, valueColor, labelColor),
        maxLines: multiLine ? null : 1,
        contextMenuBuilder: copyText != null
            ? (ctx, editableTextState) {
                return AdaptiveTextSelectionToolbar(
                  anchors: editableTextState.contextMenuAnchors,
                  children: [
                    TextSelectionToolbarTextButton(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: copyText));
                        editableTextState.hideToolbar();
                        showTelegramToast(
                            context, 'Copied to clipboard');
                      },
                      child: Text(copyLabel ?? 'Copy'),
                    ),
                  ],
                );
              }
            : null,
      );
    } else {
      valueWidget = SelectableText(
        displayValue,
        maxLines: multiLine ? null : 1,
        style: TextStyle(
          color: onTap != null ? labelColor : valueColor,
          fontSize: 14,
        ),
        contextMenuBuilder: copyText != null
            ? (ctx, editableTextState) {
                return AdaptiveTextSelectionToolbar(
                  anchors: editableTextState.contextMenuAnchors,
                  children: [
                    TextSelectionToolbarTextButton(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: copyText));
                        editableTextState.hideToolbar();
                        showTelegramToast(
                            context, 'Copied to clipboard');
                      },
                      child: Text(copyLabel ?? 'Copy'),
                    ),
                  ],
                );
              }
            : null,
      );
    }

    Widget content = Padding(
      padding: const EdgeInsets.fromLTRB(
        _kInfoPaddingH,
        _kInfoPaddingTop,
        _kInfoPaddingH,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          valueWidget,
        ],
      ),
    );

    if (onTap != null) {
      content = GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: content,
        ),
      );
    }

    return content;
  }

  TextSpan _parseTextWithEntities(
      String text, Color defaultColor, Color linkColor) {
    final urlRegex = RegExp(
        r'(https?://[^\s<>\)\]]+)|(@\w+)|(#\w+)',
        caseSensitive: false);
    final matches = urlRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return TextSpan(
        text: text,
        style: TextStyle(color: defaultColor, fontSize: 14),
      );
    }
    final spans = <InlineSpan>[];
    int lastEnd = 0;
    for (final m in matches) {
      if (m.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, m.start),
          style: TextStyle(color: defaultColor, fontSize: 14),
        ));
      }
      final matchText = m.group(0)!;
      spans.add(TextSpan(
        text: matchText,
        style: TextStyle(color: linkColor, fontSize: 14),
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            String url = matchText;
            if (matchText.startsWith('@')) {
              url = 'https://t.me/${matchText.substring(1)}';
            } else if (matchText.startsWith('#')) {
              return;
            }
            launchUrl(Uri.parse(url),
                mode: LaunchMode.externalApplication);
          },
      ));
      lastEnd = m.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: TextStyle(color: defaultColor, fontSize: 14),
      ));
    }
    return TextSpan(children: spans);
  }

  String _formatPhone(String phone) {
    if (phone.startsWith('+')) return phone;
    return '+$phone';
  }

  String _formatBirthday(int day, int month, int year) {
    const months = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final monthName = month >= 1 && month <= 12 ? months[month] : '';
    if (year > 0) {
      return '$monthName $day, $year';
    }
    return '$monthName $day';
  }

  bool _isBirthdayToday(int day, int month) {
    final now = DateTime.now();
    return now.day == day && now.month == month;
  }

  Widget _buildButtons(ThemeData theme, bool isDark) {
    final buttonColor =
        isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd);

    String? actionLabel;
    if (!_isSelf) {
      if (_isDm) {
        actionLabel = 'Send Message';
      } else if (_isChannel) {
        actionLabel = 'View Channel';
      } else {
        actionLabel = 'View Group';
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        children: [
          if (actionLabel != null) ...[
            Expanded(
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  final chatState = context.read<ChatState>();
                  final chat = chatState.chats
                      .where((c) =>
                          c.chatId == widget.peerId &&
                          c.accountId == widget.accountId)
                      .firstOrNull;
                  if (chat != null) chatState.openChat(chat);
                },
                child: Text(
                  actionLabel,
                  style: TextStyle(
                    color: buttonColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Close',
                style: TextStyle(
                  color: buttonColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  String _initials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }
}

class _PhotoProgressBarsPainter extends CustomPainter {
  final int count;
  final int activeIndex;
  final Color barColor;
  final double gap;
  final double inactiveOpacity;

  _PhotoProgressBarsPainter({
    required this.count,
    required this.activeIndex,
    required this.barColor,
    required this.gap,
    required this.inactiveOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (count <= 1) return;
    final totalGap = gap * (count - 1);
    final barWidth = (size.width - totalGap) / count;
    if (barWidth <= 0) return;
    final radius = Radius.circular(size.height / 2);
    for (int i = 0; i < count; i++) {
      final x = i * (barWidth + gap);
      final isActive = i == activeIndex;
      final paint = Paint()
        ..color =
            barColor.withValues(alpha: isActive ? 1.0 : inactiveOpacity)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromLTRBR(x, 0, x + barWidth, size.height, radius),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PhotoProgressBarsPainter old) =>
      old.count != count ||
      old.activeIndex != activeIndex ||
      old.barColor != barColor;
}
