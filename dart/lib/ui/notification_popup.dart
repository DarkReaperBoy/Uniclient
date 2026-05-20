import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../notifications/notification_system.dart';
import '../theme/telegram_palette.dart';

const _notifyWidth = 320.0;
const _notifyWidthTopCenter = 480.0;
const _notifyMinHeight = 80.0;
const _notifyDeltaX = 6.0;
const _notifyDeltaY = 7.0;
const _photoSize = 62.0;
const _photoPos = 9.0;
const _closeSize = 30.0;
const _closePosRight = 1.0;
const _closePosTop = 2.0;
const _textLeft = 83.0; // photoPos + photoSize + 12
const _textTop = 7.0;
const _itemTopOffset = 12.0;
const _borderWidth = 1.0;
const _hideAllHeight = 36.0;
const _replyButtonSize = 36.0;
const _replyFieldMinH = 36.0;
const _replyFieldMaxH = 72.0;

const _fadeInDuration = Duration(milliseconds: 150);
const _slowHideDuration = Duration(milliseconds: 4000);
const _fastHideDuration = Duration(milliseconds: 150);
const _shiftDuration = Duration(milliseconds: 150);
const _actionsFadeDuration = Duration(milliseconds: 200);
const _waitBeforeHide = Duration(milliseconds: 3000);

class _PopupState {
  final String id;
  final DefaultNotificationItem item;
  double opacity;
  double targetY;
  double currentY;
  bool hiding;
  bool hovered;
  bool replyOpen;
  double replyHeight;
  Timer? hideWaitTimer;
  Timer? hideAnimTimer;
  final TextEditingController replyController = TextEditingController();

  _PopupState({
    required this.id,
    required this.item,
    this.opacity = 0.0,
    this.targetY = 0.0,
    this.currentY = 0.0,
    this.hiding = false,
    this.hovered = false,
    this.replyOpen = false,
    this.replyHeight = _replyFieldMinH,
  });

  double get totalHeight {
    final base = _notifyMinHeight;
    if (replyOpen) return base + replyHeight + _borderWidth;
    return base;
  }

  void dispose() {
    hideWaitTimer?.cancel();
    hideAnimTimer?.cancel();
    replyController.dispose();
  }
}

class NotificationPopupOverlay extends StatefulWidget {
  final DefaultManager manager;
  final void Function(String accountId, String chatId) onTap;
  final void Function(String accountId, String chatId)? onCtrlTap;
  final void Function(String accountId, String chatId, String text)?
      onReplySend;
  final NotificationSettings settings;
  final bool isPasscodeLocked;

  const NotificationPopupOverlay({
    super.key,
    required this.manager,
    required this.onTap,
    this.onCtrlTap,
    this.onReplySend,
    this.settings = const NotificationSettings(),
    this.isPasscodeLocked = false,
  });

  @override
  State<NotificationPopupOverlay> createState() =>
      _NotificationPopupOverlayState();
}

class _NotificationPopupOverlayState extends State<NotificationPopupOverlay>
    with TickerProviderStateMixin {
  final List<_PopupState> _popups = [];
  bool _showHideAll = false;
  bool _hasReceivedInput = false;

  @override
  void initState() {
    super.initState();
    widget.manager.onShow = _onShow;
    widget.manager.onDismiss = _onDismissExternal;
    widget.manager.onStartHiding = _onStartHiding;
    widget.manager.onUpdateDisplay = _onUpdateDisplay;
    widget.manager.onHideAllChanged = _updateHideAllVisibility;
    widget.manager.isStickyCheck = _isPopupSticky;
  }

  bool _isPopupSticky(String id) {
    final popup = _popups.where((p) => p.id == id).firstOrNull;
    if (popup == null) return false;
    return popup.hovered || popup.replyOpen;
  }

  @override
  void didUpdateWidget(NotificationPopupOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manager != widget.manager) {
      widget.manager.onShow = _onShow;
      widget.manager.onDismiss = _onDismissExternal;
      widget.manager.onStartHiding = _onStartHiding;
      widget.manager.onUpdateDisplay = _onUpdateDisplay;
      widget.manager.onHideAllChanged = _updateHideAllVisibility;
      widget.manager.isStickyCheck = _isPopupSticky;
    }
  }

  void _onShow(DefaultNotificationItem item) {
    if (_popups.any((p) => p.id == item.id)) return;
    final popup = _PopupState(id: item.id, item: item);
    _hasReceivedInput = false;
    setState(() {
      _popups.add(popup);
      _recalcPositions();
    });
    Future.delayed(const Duration(milliseconds: 16), () {
      if (!mounted) return;
      setState(() => popup.opacity = 1.0);
      _startHideCountdown(popup);
    });
  }

  void _onStartHiding(String id) {
    final popup = _popups.where((p) => p.id == id).firstOrNull;
    if (popup == null || popup.hovered || popup.replyOpen) return;
    _startSlowHide(popup);
  }

  void _onUpdateDisplay(DefaultNotificationItem item) {
    if (!mounted) return;
    setState(() {});
  }

  void _onUserInput() {
    if (!_hasReceivedInput) {
      _hasReceivedInput = true;
    }
    widget.manager.onUserInput();
  }

  void _startHideCountdown(_PopupState popup) {
    popup.hideWaitTimer?.cancel();
    if (!_hasReceivedInput) {
      if (!Platform.isWindows) {
        _hasReceivedInput = true;
        _scheduleHideAfterWait(popup);
      } else {
        popup.hideWaitTimer = Timer.periodic(
          const Duration(milliseconds: 300),
          (timer) {
            if (!mounted) { timer.cancel(); return; }
            if (_hasReceivedInput) {
              timer.cancel();
              _scheduleHideAfterWait(popup);
            }
          },
        );
      }
    } else {
      _scheduleHideAfterWait(popup);
    }
  }

  void _scheduleHideAfterWait(_PopupState popup) {
    popup.hideWaitTimer?.cancel();
    popup.hideWaitTimer = Timer(_waitBeforeHide, () {
      if (!mounted || popup.hovered || popup.replyOpen) return;
      if (_anyReplyOpen()) return;
      _startSlowHide(popup);
    });
  }

  void _startSlowHide(_PopupState popup) {
    if (popup.hiding) return;
    popup.hiding = true;
    setState(() => popup.opacity = 0.0);
    popup.hideAnimTimer?.cancel();
    popup.hideAnimTimer = Timer(_slowHideDuration, () {
      _removePopup(popup.id);
    });
  }

  void _startFastHide(_PopupState popup) {
    popup.hiding = true;
    setState(() => popup.opacity = 0.0);
    popup.hideAnimTimer?.cancel();
    popup.hideAnimTimer = Timer(_fastHideDuration, () {
      _removePopup(popup.id);
    });
  }

  void _removePopup(String id) {
    final popup = _popups.where((p) => p.id == id).firstOrNull;
    if (popup == null) return;
    popup.dispose();
    setState(() {
      _popups.removeWhere((p) => p.id == id);
      _recalcPositions();
    });
    widget.manager.dismiss(id);
  }

  void _onDismissExternal(String id) {
    final popup = _popups.where((p) => p.id == id).firstOrNull;
    if (popup == null) return;
    popup.dispose();
    setState(() {
      _popups.removeWhere((p) => p.id == id);
      _recalcPositions();
    });
  }

  void _updateHideAllVisibility() {
    if (!mounted) return;
    setState(() => _showHideAll = widget.manager.showHideAll);
  }

  bool _anyReplyOpen() => _popups.any((p) => p.replyOpen);

  void _onHoverEnter(_PopupState popup) {
    popup.hovered = true;
    widget.manager.stopAllHiding();
    for (final p in _popups) {
      p.hideWaitTimer?.cancel();
      if (p.hiding && !p.replyOpen) {
        p.hiding = false;
        p.hideAnimTimer?.cancel();
      }
    }
    setState(() {
      for (final p in _popups) {
        p.opacity = 1.0;
      }
    });
  }

  void _onHoverExit(_PopupState popup) {
    popup.hovered = false;
    if (_anyReplyOpen()) return;
    widget.manager.startAllHiding();
    for (final p in _popups) {
      if (!p.hovered && !p.replyOpen) {
        _startHideCountdown(p);
      }
    }
  }

  void _onTapNotification(_PopupState popup) {
    final ctrlHeld =
        HardwareKeyboard.instance.logicalKeysPressed.contains(
            LogicalKeyboardKey.controlLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
            LogicalKeyboardKey.controlRight);
    if (ctrlHeld && widget.onCtrlTap != null) {
      widget.onCtrlTap!(popup.item.data.accountId, popup.item.data.chatId);
    } else {
      widget.onTap(popup.item.data.accountId, popup.item.data.chatId);
    }
    widget.manager.clearForChat(
        popup.item.data.accountId, popup.item.data.chatId);
  }

  void _onRightClickDismiss(_PopupState popup) {
    _startFastHide(popup);
  }

  void _onCloseClick(_PopupState popup) {
    _startFastHide(popup);
  }

  void _onReplyClick(_PopupState popup) {
    setState(() {
      popup.replyOpen = true;
      popup.hideWaitTimer?.cancel();
      popup.hiding = false;
      popup.hideAnimTimer?.cancel();
      for (final p in _popups) {
        p.hideWaitTimer?.cancel();
        if (p.hiding) {
          p.hiding = false;
          p.hideAnimTimer?.cancel();
        }
        p.opacity = 1.0;
      }
      _recalcPositions();
    });
  }

  void _onReplySend(_PopupState popup) {
    final text = popup.replyController.text.trim();
    if (text.isEmpty) return;
    widget.onReplySend
        ?.call(popup.item.data.accountId, popup.item.data.chatId, text);
    for (final p in List.of(_popups)) {
      if (p.id == popup.id) {
        _startFastHide(p);
      } else {
        _startSlowHide(p);
      }
    }
  }

  void _onReplyCancel(_PopupState popup) {
    _startFastHide(popup);
  }

  void _hideAll() {
    for (final p in List.of(_popups)) {
      p.dispose();
    }
    setState(() => _popups.clear());
    widget.manager.hideAll();
  }

  void _recalcPositions() {
    final corner = widget.manager.corner;
    final isBottom =
        corner == NotificationCorner.bottomLeft ||
        corner == NotificationCorner.bottomRight;

    double shift = _notifyDeltaY;

    final ordered = isBottom ? _popups.reversed.toList() : _popups.toList();
    for (final p in ordered) {
      p.targetY = shift;
      shift += p.totalHeight + _notifyDeltaY;
    }
  }

  @override
  void dispose() {
    for (final p in _popups) {
      p.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_popups.isEmpty) return const SizedBox.shrink();

    final palette = PaletteProvider.maybeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final corner = widget.manager.corner;
    final isTopCenter = corner == NotificationCorner.topCenter;
    final width = isTopCenter ? _notifyWidthTopCenter : _notifyWidth;
    final size = MediaQuery.of(context).size;

    final bgColor =
        palette?.windowBg ?? (isDark ? const Color(0xFF17212B) : Colors.white);
    final borderColor = palette?.windowShadowFgFallback ??
        (isDark ? const Color(0xFF17212B) : const Color(0xFFF1F1F1));
    final titleColor = palette?.windowFg ??
        (isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000));
    final bodyColor = palette?.windowSubTextFg ??
        (isDark ? const Color(0xFF8899A6) : const Color(0xFF666666));
    final closeColor = palette?.menuIconFg ??
        (isDark ? const Color(0xFF8899A6) : const Color(0xFF999999));
    final accentColor = palette?.windowBgActive ??
        (context.palette.windowBgActive);

    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final isLeftCorner = corner == NotificationCorner.topLeft ||
        corner == NotificationCorner.bottomLeft;
    final isLeft = isLeftCorner != isRtl;
    final isBottom = corner == NotificationCorner.bottomLeft ||
        corner == NotificationCorner.bottomRight;

    double xPos;
    if (isTopCenter) {
      xPos = (size.width - width) / 2;
    } else if (isLeft) {
      xPos = _notifyDeltaX;
    } else {
      xPos = size.width - width - _notifyDeltaX;
    }

    final children = <Widget>[];

    for (final popup in _popups) {
      final double yPos;
      if (isBottom) {
        yPos = size.height - popup.targetY - popup.totalHeight;
      } else {
        yPos = popup.targetY;
      }

      final hideReply = shouldHideReplyButton(
        popup.item.data,
        widget.settings,
        isPasscodeLocked: widget.isPasscodeLocked,
      );

      children.add(
        _NotificationPopupWidget(
          key: ValueKey(popup.id),
          popup: popup,
          x: xPos,
          y: yPos,
          width: width,
          hideReply: hideReply,
          bgColor: bgColor,
          borderColor: borderColor,
          titleColor: titleColor,
          bodyColor: bodyColor,
          closeColor: closeColor,
          accentColor: accentColor,
          settings: widget.settings,
          onHoverEnter: () => _onHoverEnter(popup),
          onHoverExit: () => _onHoverExit(popup),
          onTap: () => _onTapNotification(popup),
          onRightClick: () => _onRightClickDismiss(popup),
          onClose: () => _onCloseClick(popup),
          onReplyClick: () => _onReplyClick(popup),
          onReplySend: () => _onReplySend(popup),
          onReplyCancel: () => _onReplyCancel(popup),
          onReplyHeightChanged: (h) {
            if (popup.replyHeight != h) {
              setState(() {
                popup.replyHeight = h;
                _recalcPositions();
              });
            }
          },
        ),
      );
    }

    if (_showHideAll && (_popups.length >= 2 || widget.manager.hasQueue)) {
      final lastShift = _popups.fold<double>(
          _notifyDeltaY, (sum, p) => sum + p.totalHeight + _notifyDeltaY);
      final hideAllY = isBottom
          ? size.height - lastShift - _hideAllHeight
          : lastShift;

      children.add(
        Positioned(
          left: xPos,
          top: hideAllY,
          child: _HideAllButton(
            width: width,
            bgColor: bgColor,
            borderColor: borderColor,
            accentColor: accentColor,
            onTap: _hideAll,
          ),
        ),
      );
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onUserInput(),
      onPointerHover: (_) => _onUserInput(),
      child: Stack(children: children),
    );
  }
}

class _NotificationPopupWidget extends StatelessWidget {
  final _PopupState popup;
  final double x, y, width;
  final bool hideReply;
  final Color bgColor, borderColor, titleColor, bodyColor, closeColor,
      accentColor;
  final VoidCallback onHoverEnter, onHoverExit, onTap, onRightClick, onClose,
      onReplyClick, onReplySend, onReplyCancel;
  final NotificationSettings settings;
  final ValueChanged<double>? onReplyHeightChanged;

  const _NotificationPopupWidget({
    super.key,
    required this.popup,
    required this.x,
    required this.y,
    required this.width,
    required this.hideReply,
    required this.bgColor,
    required this.borderColor,
    required this.titleColor,
    required this.bodyColor,
    required this.closeColor,
    required this.accentColor,
    required this.onHoverEnter,
    required this.onHoverExit,
    required this.onTap,
    required this.onRightClick,
    required this.onClose,
    required this.onReplyClick,
    required this.onReplySend,
    required this.onReplyCancel,
    required this.settings,
    this.onReplyHeightChanged,
  });

  @override
  Widget build(BuildContext context) {
    final data = popup.item.data;
    final hideEasing =
        popup.hiding ? Curves.easeInCirc : Curves.linear;
    final hideDuration =
        popup.hiding ? _slowHideDuration : _fadeInDuration;
    final content = composeNotificationContent(data, settings);
    final nameHidden = !settings.previewName;

    return AnimatedPositioned(
      duration: _shiftDuration,
      left: x,
      top: y,
      child: MouseRegion(
        onEnter: (_) => onHoverEnter(),
        onExit: (_) => onHoverExit(),
        child: AnimatedOpacity(
          opacity: popup.opacity,
          duration: hideDuration,
          curve: hideEasing,
          child: GestureDetector(
            onTap: onTap,
            onSecondaryTap: onRightClick,
            child: Container(
              width: width,
              constraints:
                  const BoxConstraints(minHeight: _notifyMinHeight),
              decoration: BoxDecoration(
                color: bgColor,
                border:
                    Border.all(color: borderColor, width: _borderWidth),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: _notifyMinHeight,
                    child: Stack(
                      children: [
                        Positioned(
                          left: _photoPos,
                          top: _photoPos,
                          child: _Avatar(
                            name: content.title,
                            avatarPath: nameHidden ? '' : data.avatarPath,
                            accentColor: accentColor,
                            forceHiddenPlaceholder: nameHidden,
                          ),
                        ),
                        Positioned(
                          left: _textLeft,
                          top: _textTop,
                          right: _closeSize + _closePosRight + 4,
                          child: Text(
                            content.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: titleColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Positioned(
                          left: _textLeft,
                          top: _itemTopOffset + 13,
                          right: _closeSize + _closePosRight + 4,
                          bottom: 4,
                          child: ShaderMask(
                            shaderCallback: (Rect bounds) {
                              return const LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  Colors.white,
                                  Colors.white,
                                  Colors.transparent,
                                ],
                                stops: [0.0, 0.85, 1.0],
                              ).createShader(bounds);
                            },
                            blendMode: BlendMode.dstIn,
                            child: Text.rich(
                              _buildBodySpan(content, titleColor, bodyColor),
                              maxLines: 2,
                              overflow: TextOverflow.clip,
                            ),
                          ),
                        ),
                        Positioned(
                          right: _closePosRight,
                          top: _closePosTop,
                          child: _CloseButton(
                            color: closeColor,
                            onTap: onClose,
                          ),
                        ),
                        if (!popup.replyOpen && !hideReply)
                          Positioned(
                            right: 9,
                            bottom: 9,
                            child: IgnorePointer(
                              ignoring: !popup.hovered,
                              child: AnimatedOpacity(
                                opacity: popup.hovered ? 1.0 : 0.0,
                                duration: _actionsFadeDuration,
                                child: _ReplyButton(
                                  accentColor: accentColor,
                                  onTap: onReplyClick,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (popup.replyOpen)
                    _ReplyField(
                      controller: popup.replyController,
                      width: width,
                      accentColor: accentColor,
                      bgColor: bgColor,
                      bodyColor: bodyColor,
                      onSend: onReplySend,
                      onCancel: onReplyCancel,
                      onHeightChanged: onReplyHeightChanged,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InlineSpan _buildBodySpan(NotificationContent content, Color titleColor, Color bodyColor) {
    final bodySpans = _buildEntitySpans(content.body, content.bodyEntities, bodyColor, titleColor);
    if (content.subtitle.isNotEmpty) {
      return TextSpan(children: [
        TextSpan(
          text: '${content.subtitle}: ',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: titleColor),
        ),
        ...bodySpans,
      ]);
    }
    if (bodySpans.length == 1) return bodySpans.first;
    return TextSpan(children: bodySpans);
  }

  List<TextSpan> _buildEntitySpans(String text, List<NotifEntity> entities, Color bodyColor, Color accentColor) {
    if (entities.isEmpty || text.isEmpty) {
      return [TextSpan(text: text, style: TextStyle(fontSize: 13, color: bodyColor))];
    }
    final sorted = [...entities]..sort((a, b) => a.offset.compareTo(b.offset));
    final spans = <TextSpan>[];
    var pos = 0;
    for (final e in sorted) {
      if (e.offset > pos) {
        spans.add(TextSpan(text: text.substring(pos, e.offset), style: TextStyle(fontSize: 13, color: bodyColor)));
      }
      final end = (e.offset + e.length).clamp(0, text.length);
      final segment = text.substring(e.offset.clamp(0, text.length), end);
      spans.add(TextSpan(text: segment, style: _entityStyle(e.type, bodyColor, accentColor)));
      pos = end;
    }
    if (pos < text.length) {
      spans.add(TextSpan(text: text.substring(pos), style: TextStyle(fontSize: 13, color: bodyColor)));
    }
    return spans;
  }

  TextStyle _entityStyle(String type, Color bodyColor, Color accentColor) {
    return switch (type) {
      'bold' => TextStyle(fontSize: 13, color: bodyColor, fontWeight: FontWeight.w600),
      'italic' => TextStyle(fontSize: 13, color: bodyColor, fontStyle: FontStyle.italic),
      'code' || 'pre' => TextStyle(fontSize: 12, color: bodyColor, fontFamily: 'monospace'),
      'underline' => TextStyle(fontSize: 13, color: bodyColor, decoration: TextDecoration.underline),
      'strikethrough' => TextStyle(fontSize: 13, color: bodyColor, decoration: TextDecoration.lineThrough),
      'mention' || 'mention_name' || 'url' || 'text_url' || 'hashtag' || 'cashtag' || 'bot_command' =>
        TextStyle(fontSize: 13, color: accentColor),
      _ => TextStyle(fontSize: 13, color: bodyColor),
    };
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final String avatarPath;
  final Color accentColor;
  final bool forceHiddenPlaceholder;

  const _Avatar({
    required this.name,
    required this.avatarPath,
    required this.accentColor,
    this.forceHiddenPlaceholder = false,
  });

  @override
  Widget build(BuildContext context) {
    if (forceHiddenPlaceholder) {
      return const _HiddenUserpicPlaceholder();
    }
    if (avatarPath.isNotEmpty) {
      return ClipOval(
        child: Image.file(
          File(avatarPath),
          width: _photoSize,
          height: _photoSize,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initialsFallback(),
        ),
      );
    }
    return _initialsFallback();
  }

  Widget _initialsFallback() {
    return Container(
      width: _photoSize,
      height: _photoSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accentColor,
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(name),
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
    );
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

class _HiddenUserpicPlaceholder extends StatelessWidget {
  const _HiddenUserpicPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icon/icon_64.png',
      width: _photoSize,
      height: _photoSize,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: _photoSize,
        height: _photoSize,
        color: context.palette.windowBgActive,
        alignment: Alignment.center,
        child: const Text(
          'U',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _HideAllButton extends StatefulWidget {
  final double width;
  final Color bgColor;
  final Color borderColor;
  final Color accentColor;
  final VoidCallback onTap;

  const _HideAllButton({
    required this.width,
    required this.bgColor,
    required this.borderColor,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_HideAllButton> createState() => _HideAllButtonState();
}

class _HideAllButtonState extends State<_HideAllButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgOver = isDark ? const Color(0xFF3A4958) : const Color(0xFFE8E8E8);
    final fgOver = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: widget.width,
          height: _hideAllHeight,
          decoration: BoxDecoration(
            color: _hovered ? bgOver : widget.bgColor,
            border: Border.all(color: widget.borderColor, width: _borderWidth),
          ),
          alignment: Alignment.center,
          child: Text(
            'Hide All',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _hovered ? fgOver : widget.accentColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _CloseButton({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onSecondaryTap: onTap,
      child: SizedBox(
        width: _closeSize,
        height: _closeSize,
        child: Center(
          child: Icon(Icons.close, size: 10, color: color),
        ),
      ),
    );
  }
}

class _ReplyButton extends StatelessWidget {
  final Color accentColor;
  final VoidCallback onTap;

  const _ReplyButton({required this.accentColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: accentColor,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: const Text(
          'REPLY',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _ReplyField extends StatefulWidget {
  final TextEditingController controller;
  final double width;
  final Color accentColor, bgColor, bodyColor;
  final VoidCallback onSend, onCancel;
  final ValueChanged<double>? onHeightChanged;

  const _ReplyField({
    required this.controller,
    required this.width,
    required this.accentColor,
    required this.bgColor,
    required this.bodyColor,
    required this.onSend,
    required this.onCancel,
    this.onHeightChanged,
  });

  @override
  State<_ReplyField> createState() => _ReplyFieldState();
}

class _ReplyFieldState extends State<_ReplyField> {
  late final FocusNode _focusNode;
  final GlobalKey _fieldKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    widget.controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        widget.onHeightChanged?.call(box.size.height);
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(
          left: _borderWidth, right: _borderWidth, bottom: _borderWidth),
      child: Row(
        children: [
          Expanded(
            child: ConstrainedBox(
              key: _fieldKey,
              constraints: const BoxConstraints(
                minHeight: _replyFieldMinH,
                maxHeight: _replyFieldMaxH,
              ),
              child: Focus(
                focusNode: _focusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  if (event.logicalKey == LogicalKeyboardKey.escape) {
                    widget.onCancel();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.enter) {
                    final shift = HardwareKeyboard.instance.logicalKeysPressed
                        .any((k) =>
                            k == LogicalKeyboardKey.shiftLeft ||
                            k == LogicalKeyboardKey.shiftRight);
                    if (!shift) {
                      widget.onSend();
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: widget.controller,
                  autofocus: true,
                  maxLines: null,
                  maxLength: 4096,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  buildCounter: (_, {required currentLength, required isFocused, required maxLength}) => null,
                  style: TextStyle(fontSize: 13, color: widget.bodyColor),
                  decoration: InputDecoration(
                    hintText: 'Reply...',
                    hintStyle: TextStyle(fontSize: 13, color: widget.bodyColor.withValues(alpha: 0.5)),
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.fromLTRB(8, 8, 8, 6),
                    isDense: true,
                  ),
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: widget.onSend,
            child: SizedBox(
              width: _replyButtonSize,
              height: _replyButtonSize,
              child: Icon(Icons.send, size: 18, color: widget.accentColor),
            ),
          ),
        ],
      ),
    );
  }
}
