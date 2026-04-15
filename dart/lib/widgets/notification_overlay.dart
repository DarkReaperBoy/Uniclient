import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/theme.dart';

// ── Notification data types ──

enum _NotifKind { message, status }

class _NotifEntry {
  final _NotifKind kind;

  // Message fields
  final String senderName;
  final String text;
  final String chatTitle;
  final VoidCallback? onTap;

  // Status fields
  final IconData? icon;
  final Color? color;

  final Duration autoDismiss;

  const _NotifEntry.message({
    required this.senderName,
    required this.text,
    this.chatTitle = '',
    this.onTap,
  })  : kind = _NotifKind.message,
        icon = null,
        color = null,
        autoDismiss = const Duration(seconds: 4);

  const _NotifEntry.status({
    required this.text,
    this.icon,
    this.color,
  })  : kind = _NotifKind.status,
        senderName = '',
        chatTitle = '',
        onTap = null,
        autoDismiss = const Duration(seconds: 2);
}

// ── NotificationManager — singleton access from anywhere ──

class NotificationManager extends InheritedWidget {
  final NotificationOverlayState _state;

  const NotificationManager({
    super.key,
    required NotificationOverlayState state,
    required super.child,
  }) : _state = state;

  static NotificationManager? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<NotificationManager>();
  }

  static NotificationManager of(BuildContext context) {
    final result = maybeOf(context);
    assert(result != null, 'No NotificationManager found in context');
    return result!;
  }

  /// Show a message notification toast + native desktop notification.
  void showMessageNotification(
    String senderName,
    String text, {
    String chatTitle = '',
    VoidCallback? onTap,
  }) {
    _state._enqueue(_NotifEntry.message(
      senderName: senderName,
      text: text,
      chatTitle: chatTitle,
      onTap: onTap,
    ));
    // Fire native desktop notification (non-blocking).
    _sendDesktopNotification(
      chatTitle.isNotEmpty ? '$senderName in $chatTitle' : senderName,
      text,
    );
  }

  static void _sendDesktopNotification(String title, String body) {
    if (Platform.isLinux) {
      // notify-send is available on most Linux desktops.
      Process.run('notify-send', [
        '--app-name=UniClient',
        '--icon=mail-message-new',
        '--urgency=normal',
        title,
        body,
      ]).then((_) {}, onError: (_) {}); // ignore if notify-send is not installed
    }
  }

  /// Show a status notification toast (e.g., "Connected", "Disconnected").
  void showStatusNotification(
    String text, {
    IconData? icon,
    Color? color,
  }) {
    _state._enqueue(_NotifEntry.status(
      text: text,
      icon: icon,
      color: color,
    ));
  }

  /// Dismiss the currently visible notification immediately.
  void dismiss() {
    _state._dismissCurrent();
  }

  @override
  bool updateShouldNotify(NotificationManager oldWidget) =>
      _state != oldWidget._state;
}

// ── NotificationOverlay — wraps the app body ──

class NotificationOverlay extends StatefulWidget {
  final Widget child;

  const NotificationOverlay({super.key, required this.child});

  @override
  State<NotificationOverlay> createState() => NotificationOverlayState();
}

class NotificationOverlayState extends State<NotificationOverlay>
    with SingleTickerProviderStateMixin {
  final List<_NotifEntry> _queue = [];
  _NotifEntry? _current;
  bool _visible = false;
  Timer? _autoDismissTimer;
  Timer? _gapTimer;

  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    ));

    _slideController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        setState(() {
          _current = null;
          _visible = false;
        });
        // After dismiss animation completes, wait 500ms before next.
        _gapTimer?.cancel();
        if (_queue.isNotEmpty) {
          _gapTimer = Timer(const Duration(milliseconds: 500), _showNext);
        }
      }
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _gapTimer?.cancel();
    _slideController.dispose();
    super.dispose();
  }

  void _enqueue(_NotifEntry entry) {
    _queue.add(entry);
    if (_current == null && !_visible) {
      _showNext();
    }
  }

  void _showNext() {
    if (_queue.isEmpty) return;
    final entry = _queue.removeAt(0);
    setState(() {
      _current = entry;
      _visible = true;
    });
    _slideController.forward(from: 0);
    _autoDismissTimer?.cancel();
    _autoDismissTimer = Timer(entry.autoDismiss, _dismissCurrent);
  }

  void _dismissCurrent() {
    _autoDismissTimer?.cancel();
    if (_visible && _slideController.status != AnimationStatus.reverse) {
      _slideController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationManager(
      state: this,
      child: Stack(
        children: [
          widget.child,
          if (_current != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: _current!.kind == _NotifKind.message
                      ? _buildMessageToast(_current!)
                      : _buildStatusToast(_current!),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageToast(_NotifEntry entry) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textColor = isDark ? AppColors.darkText : AppColors.lightText;
    final dimColor = isDark ? AppColors.darkTextDim : AppColors.lightTextDim;
    final mutedColor = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

    return GestureDetector(
      onTap: () {
        entry.onTap?.call();
        _dismissCurrent();
      },
      onVerticalDragEnd: (d) {
        if (d.velocity.pixelsPerSecond.dy < -100) {
          _dismissCurrent();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 0.5),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Avatar circle
                Container(
                  width: AppSizes.avatarSizeSmall,
                  height: AppSizes.avatarSizeSmall,
                  decoration: BoxDecoration(
                    color: _avatarColor(entry.senderName),
                    borderRadius: BorderRadius.circular(AppSizes.avatarSizeSmall / 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _avatarLetter(entry.senderName),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              entry.senderName,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (entry.chatTitle.isNotEmpty) ...[
                            Text(
                              '  in ',
                              style: TextStyle(
                                color: dimColor,
                                fontSize: 12,
                              ),
                            ),
                            Flexible(
                              child: Text(
                                entry.chatTitle,
                                style: TextStyle(
                                  color: mutedColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.text,
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusToast(_NotifEntry entry) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;
    final color = entry.color ?? (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted);
    return GestureDetector(
      onVerticalDragEnd: (d) {
        if (d.velocity.pixelsPerSecond.dy < -100) {
          _dismissCurrent();
        }
      },
      child: Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.3)),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 12,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (entry.icon != null) ...[
                    Icon(entry.icon, color: color, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    entry.text,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _avatarColor(String name) {
    if (name.isEmpty) return AppColors.darkTextDim;
    const colors = [
      Color(0xFF4F6EF7),
      Color(0xFF3BA55C),
      Color(0xFFFAA61A),
      Color(0xFFED4245),
      Color(0xFF9B59B6),
      Color(0xFF1ABC9C),
      Color(0xFFE67E22),
      Color(0xFF11806A),
    ];
    return colors[name.codeUnitAt(0) % colors.length];
  }

  String _avatarLetter(String name) {
    if (name.isEmpty) return '?';
    return name[0].toUpperCase();
  }
}
