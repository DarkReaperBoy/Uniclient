import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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
    barrierColor: Colors.black54,
    transitionDuration: _kAnimDuration,
    transitionBuilder: (ctx, anim, secondaryAnim, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCirc),
        child: child,
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

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _loadingProfile = true);
    try {
      final engine = context.read<EngineService>();
      final profile = await engine.getUserProfile(widget.accountId, widget.peerId);
      if (mounted) {
        setState(() {
          _profile = profile;
          _loadingProfile = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  bool get _isDm => widget.peerType == ChatType.dm;
  bool get _isGroup => widget.peerType == ChatType.group;
  bool get _isChannel => widget.peerType == ChatType.channel;

  bool get _isSelf {
    try {
      final chatState = context.read<ChatState>();
      final chat = chatState.activeChat;
      if (chat != null && chat.title == 'Saved Messages' && widget.peerId == chat.chatId) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenSize = MediaQuery.of(context).size;
    final maxHeight = screenSize.height - 40;

    return Center(
      child: KeyboardListener(
        focusNode: FocusNode()..requestFocus(),
        autofocus: true,
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
          }
        },
        child: Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _kBoxWidth,
              maxHeight: maxHeight,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_kBoxRadius),
              child: Container(
                color: isDark ? const Color(0xFF17212b) : Colors.white,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildCover(theme, isDark),
                    Flexible(
                      child: Scrollbar(
                        thickness: _kScrollBarWidth,
                        radius: const Radius.circular(4),
                        child: SingleChildScrollView(
                          child: _buildInfoRows(theme, isDark),
                        ),
                      ),
                    ),
                    _buildButtons(theme, isDark),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover(ThemeData theme, bool isDark) {
    final hasAvatar = widget.avatarPath.isNotEmpty;
    final displayName = _profile?.displayName.isNotEmpty == true
        ? _profile!.displayName
        : widget.peerName;

    String statusText;
    if (_isDm) {
      statusText = _profile?.isBot == true ? 'bot' : 'last seen recently';
    } else if (_isChannel) {
      statusText = widget.memberCount > 0
          ? '${_formatCount(widget.memberCount)} subscribers'
          : 'channel';
    } else {
      statusText = widget.memberCount > 0
          ? '${_formatCount(widget.memberCount)} members'
          : 'group';
    }

    return SizedBox(
      width: _kCoverSize,
      height: _kCoverSize,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasAvatar)
            Image.file(
              File(widget.avatarPath),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: Colors.black),
            )
          else
            Container(
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
            ),
          // Bottom shadow gradient for text readability
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _kShadowHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.31),
                  ],
                ),
              ),
            ),
          ),
          // Name
          Positioned(
            left: _kNameX,
            right: _kNameX,
            bottom: _kNameY,
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
          // Status
          Positioned(
            left: _kStatusX,
            right: _kStatusX,
            bottom: _kStatusY,
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
        ],
      ),
    );
  }

  Widget _buildInfoRows(ThemeData theme, bool isDark) {
    final rows = <Widget>[];
    final labelColor = isDark
        ? const Color(0xFF6ab3f3)
        : const Color(0xFF168acd);
    final valueColor = isDark ? Colors.white : Colors.black87;

    if (_isDm && _profile != null) {
      if (_profile!.phone.isNotEmpty) {
        rows.add(_infoRow(
          label: 'Mobile',
          value: _profile!.phone,
          labelColor: labelColor,
          valueColor: valueColor,
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: _profile!.phone));
            showTelegramToast(context, 'Phone copied');
          },
        ));
      }
      if (_profile!.bio.isNotEmpty) {
        rows.add(_infoRow(
          label: _profile!.isBot ? 'About' : 'Bio',
          value: _profile!.bio,
          labelColor: labelColor,
          valueColor: valueColor,
          multiLine: true,
        ));
      }
      if (_profile!.username.isNotEmpty) {
        rows.add(_infoRow(
          label: 'Username',
          value: '@${_profile!.username}',
          labelColor: labelColor,
          valueColor: valueColor,
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: '@${_profile!.username}'));
            showTelegramToast(context, 'Username copied');
          },
        ));
      }
    } else if ((_isGroup || _isChannel) && _profile != null) {
      if (_profile!.bio.isNotEmpty) {
        rows.add(_infoRow(
          label: 'About',
          value: _profile!.bio,
          labelColor: labelColor,
          valueColor: valueColor,
          multiLine: true,
        ));
      }
      if (_profile!.username.isNotEmpty) {
        rows.add(_infoRow(
          label: 'Link',
          value: 't.me/${_profile!.username}',
          labelColor: labelColor,
          valueColor: valueColor,
          onLongPress: () {
            Clipboard.setData(
                ClipboardData(text: 'https://t.me/${_profile!.username}'));
            showTelegramToast(context, 'Link copied');
          },
        ));
      }
    }

    if (rows.isEmpty && !_loadingProfile) {
      return const SizedBox.shrink();
    }

    if (_loadingProfile && rows.isEmpty) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }

  Widget _infoRow({
    required String label,
    required String value,
    required Color labelColor,
    required Color valueColor,
    bool multiLine = false,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Padding(
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
            SelectableText(
              value,
              maxLines: multiLine ? null : 1,
              style: TextStyle(
                color: valueColor,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButtons(ThemeData theme, bool isDark) {
    final buttonColor = isDark
        ? const Color(0xFF6ab3f3)
        : const Color(0xFF168acd);

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
          if (actionLabel != null)
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
          if (actionLabel != null) const SizedBox(width: 8),
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
