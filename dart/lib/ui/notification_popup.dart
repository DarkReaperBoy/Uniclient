import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart' as pkg_ffi;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../notifications/notification_system.dart';
import '../theme/telegram_palette.dart';

const _notifyWidth = 320.0;
const _notifyWidthTopCenter = 480.0;
const _notifyMinHeight = 80.0;
const _notifyDeltaX = 6.0;
const _notifyDeltaY = 7.0;
final double _photoSize = Platform.isMacOS ? 64.0 : 62.0;
const _photoPos = 9.0;
const _closeSize = 30.0;
const _closePosRight = 1.0;
const _closePosTop = 2.0;
final double _textLeft = _photoPos + _photoSize + 12.0;
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

/// Win32 GetLastInputInfo for detecting system-wide user activity on Windows.
bool _winHasRecentInput() {
  if (!Platform.isWindows) return true;
  try {
    final user32 = ffi.DynamicLibrary.open('user32.dll');
    final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
    final getLastInputInfo = user32.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<_LASTINPUTINFO>),
        int Function(ffi.Pointer<_LASTINPUTINFO>)>('GetLastInputInfo');
    final getTickCount = kernel32
        .lookupFunction<ffi.Uint32 Function(), int Function()>('GetTickCount');
    final info = pkg_ffi.calloc<_LASTINPUTINFO>();
    info.ref.cbSize = ffi.sizeOf<_LASTINPUTINFO>();
    final ok = getLastInputInfo(info);
    if (ok == 0) {
      pkg_ffi.calloc.free(info);
      return true;
    }
    final idleMs = getTickCount() - info.ref.dwTime;
    pkg_ffi.calloc.free(info);
    return idleMs < 5000;
  } catch (_) {
    return true;
  }
}

final class _LASTINPUTINFO extends ffi.Struct {
  @ffi.Uint32()
  external int cbSize;
  @ffi.Uint32()
  external int dwTime;
}

class _PopupState {
  final String id;
  final DefaultNotificationItem item;
  double opacity;
  double targetY;
  double currentY;
  bool hiding;
  bool fastHiding;
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
    this.fastHiding = false,
    this.hovered = false,
    this.replyOpen = false,
    this.replyHeight = _replyFieldMinH,
  });

  InlineSpan? _cachedBodySpan;
  NotificationContent? _cachedContent;
  int _spanColorKey = 0;

  void invalidateSpanCache() {
    _cachedBodySpan = null;
    _cachedContent = null;
    _spanColorKey = 0;
  }

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

  /// Demo master opacity: when true (the notification-position sample is on
  /// screen), every live popup + the HideAll button dims to transparent and
  /// stops intercepting pointer events. Mirrors AyuGram's _demoMasterOpacity.
  final bool demoDimmed;

  const NotificationPopupOverlay({
    super.key,
    required this.manager,
    required this.onTap,
    this.onCtrlTap,
    this.onReplySend,
    this.settings = const NotificationSettings(),
    this.isPasscodeLocked = false,
    this.demoDimmed = false,
  });

  @override
  State<NotificationPopupOverlay> createState() =>
      _NotificationPopupOverlayState();
}

class _NotificationPopupOverlayState extends State<NotificationPopupOverlay>
    with TickerProviderStateMixin {
  final List<_PopupState> _popups = [];
  bool _showHideAll = false;
  double _hideAllOpacity = 1.0;
  bool _hideAllHiding = false;
  bool _hideAllFastHiding = false;
  bool _hasReceivedInput = false;
  bool _updateDisplayScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.manager.onShow = _onShow;
    widget.manager.onDismiss = _onDismissExternal;
    widget.manager.onStartHiding = _onStartHiding;
    widget.manager.onStartHidingFast = _onStartHidingFast;
    widget.manager.onUpdateDisplay = _onUpdateDisplay;
    widget.manager.onHideAllChanged = _updateHideAllVisibility;
    widget.manager.onStartHidingHideAll = _onStartHidingHideAll;
    widget.manager.onStartHidingHideAllFast = _onStartHidingHideAllFast;
    widget.manager.onStopHidingHideAll = _onStopHidingHideAll;
    widget.manager.onCornerChanged = _onCornerChanged;
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
      widget.manager.onStartHidingFast = _onStartHidingFast;
      widget.manager.onUpdateDisplay = _onUpdateDisplay;
      widget.manager.onHideAllChanged = _updateHideAllVisibility;
      widget.manager.onStartHidingHideAll = _onStartHidingHideAll;
      widget.manager.onStartHidingHideAllFast = _onStartHidingHideAllFast;
      widget.manager.onStopHidingHideAll = _onStopHidingHideAll;
      widget.manager.onCornerChanged = _onCornerChanged;
      widget.manager.isStickyCheck = _isPopupSticky;
    }
  }

  void _onShow(DefaultNotificationItem item) {
    if (_popups.any((p) => p.id == item.id)) return;
    final popup = _PopupState(id: item.id, item: item);
    _hasReceivedInput = false;
    setState(() {
      _popups.add(popup);
      // A freshly shown notification re-activates the stack, so the HideAll
      // button returns to full opacity — matching AyuGram's moveWidgets()
      // calling _hideAll->stopHiding() whenever the button stays visible.
      _hideAllHiding = false;
      _hideAllFastHiding = false;
      _hideAllOpacity = 1.0;
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

  // HideAll / clear-all: a smooth 150ms fast fade (AyuGram hideFast), driven by
  // the manager so even a hovered/reply-open row is force-cleared.
  void _onStartHidingFast(String id) {
    final popup = _popups.where((p) => p.id == id).firstOrNull;
    if (popup == null) return;
    _startFastHide(popup);
  }

  void _onUpdateDisplay(DefaultNotificationItem item) {
    if (!mounted) return;
    final popup = _popups.where((p) => p.id == item.id).firstOrNull;
    if (popup != null) {
      popup.invalidateSpanCache();
    }
    if (!_updateDisplayScheduled) {
      _updateDisplayScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _updateDisplayScheduled = false;
        setState(() {});
      });
    }
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
            if (_hasReceivedInput || _winHasRecentInput()) {
              timer.cancel();
              _hasReceivedInput = true;
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
    popup.fastHiding = false;
    setState(() => popup.opacity = 0.0);
    popup.hideAnimTimer?.cancel();
    popup.hideAnimTimer = Timer(_slowHideDuration, () {
      _removePopup(popup.id);
    });
  }

  void _startFastHide(_PopupState popup) {
    popup.hiding = true;
    popup.fastHiding = true;
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
    final next = widget.manager.showHideAll;
    setState(() {
      // When the button transitions from hidden to shown it must start fully
      // visible rather than stuck at the opacity left over from a prior fade.
      if (next && !_showHideAll) {
        _hideAllHiding = false;
        _hideAllFastHiding = false;
        _hideAllOpacity = 1.0;
      }
      _showHideAll = next;
    });
  }

  void _onStartHidingHideAll() {
    if (!mounted) return;
    setState(() {
      _hideAllHiding = true;
      _hideAllFastHiding = false;
      _hideAllOpacity = 0.0;
    });
  }

  // Fast 150ms fade of the HideAll button (clear-all). Keeping _hideAllHiding
  // false makes the AnimatedOpacity use _fastHideDuration / linear, while
  // _hideAllFastHiding keeps the button in the tree until the fade ends.
  void _onStartHidingHideAllFast() {
    if (!mounted) return;
    setState(() {
      _hideAllHiding = false;
      _hideAllFastHiding = true;
      _hideAllOpacity = 0.0;
    });
  }

  void _onStopHidingHideAll() {
    if (!mounted) return;
    setState(() {
      _hideAllHiding = false;
      _hideAllFastHiding = false;
      _hideAllOpacity = 1.0;
    });
  }

  // AyuGram's settingsChanged(ChangeType::Corner) immediately repositions every
  // live notification AND the HideAll button via updatePosition
  // (notifications_manager_default.cpp:139-148). Recompute every popup's targetY
  // for the new orientation and rebuild — build() reads the new corner for the
  // x-position, top-center width, and the HideAll button slot, so a single
  // setState repositions the whole stack (the AnimatedPositioned rows slide to
  // their new slots). Without this, a popup already on screen stays stuck in the
  // old corner until the next show/dismiss.
  void _onCornerChanged() {
    if (!mounted) return;
    setState(() {
      _recalcPositions();
    });
  }

  bool _anyReplyOpen() => _popups.any((p) => p.replyOpen);

  void _onHoverEnter(_PopupState popup) {
    popup.hovered = true;
    widget.manager.stopAllHiding();
    for (final p in _popups) {
      p.hideWaitTimer?.cancel();
      if (p.hiding && !p.replyOpen) {
        p.hiding = false;
        p.fastHiding = false;
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
    setState(() {
      popup.hovered = false;
    });
    if (_anyReplyOpen()) return;
    // The manager begins the slow fade for every non-sticky row (and the
    // HideAll button) IMMEDIATELY via onStartHiding/onStartHidingHideAll — no
    // extra dismiss countdown. Matches AyuGram's leaveEventHook → startAllHiding
    // → hideSlow() firing at once (notifications_manager_default.cpp:202-211).
    widget.manager.startAllHiding();
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
    // Let the manager drive a smooth 150ms fast fade of every row + the button
    // (→ onStartHidingFast / onStartHidingHideAllFast) instead of clearing the
    // popups instantly — AyuGram's doClearAll() uses hideFast(), not an abrupt
    // teardown.
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
    final lightBtnBg = palette?.lightButtonBg ??
        (isDark ? const Color(0xFF17212B) : Colors.white);

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

      final hideReply = widget.onReplySend == null ||
          shouldHideReplyButton(
            popup.item.data,
            widget.settings,
            isPasscodeLocked: widget.isPasscodeLocked,
          );

      children.add(
        RepaintBoundary(
          child: _NotificationPopupWidget(
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
        ),
      );
    }

    // Keep the button mounted while it fast-fades on clear-all (_hideAllFastHiding)
    // even though _showHideAll has already flipped false, so the fade is visible.
    if ((_showHideAll || _hideAllFastHiding) &&
        (_popups.length >= 2 || widget.manager.hasQueue)) {
      final lastShift = _popups.fold<double>(
          _notifyDeltaY, (sum, p) => sum + p.totalHeight + _notifyDeltaY);
      final hideAllY = isBottom
          ? size.height - lastShift - _hideAllHeight
          : lastShift;

      children.add(
        Positioned(
          left: xPos,
          top: hideAllY,
          child: AnimatedOpacity(
            opacity: _hideAllOpacity,
            duration: _hideAllHiding ? _slowHideDuration : _fastHideDuration,
            curve: _hideAllHiding ? Curves.easeInCirc : Curves.linear,
            child: _HideAllButton(
              width: width,
              bgColor: lightBtnBg,
              borderColor: borderColor,
              accentColor: accentColor,
              onTap: _hideAll,
            ),
          ),
        ),
      );
    }

    final stack = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onUserInput(),
      onPointerHover: (_) => _onUserInput(),
      child: Stack(children: children),
    );

    // Demo master opacity: while the notification-position sample is on screen
    // (AppState.notifDemoShown → widget.demoDimmed), every live popup + the
    // HideAll button dims to transparent over notifyFastAnim (150ms) and stops
    // intercepting pointer events, so the sample stands alone — mirroring
    // AyuGram's _demoMasterOpacity / demoMasterOpacityCallback()
    // (notifications_manager_default.cpp:162-184, updateOpacity :591-593).
    return IgnorePointer(
      ignoring: widget.demoDimmed,
      child: AnimatedOpacity(
        opacity: widget.demoDimmed ? 0.0 : 1.0,
        duration: _fastHideDuration,
        curve: Curves.linear,
        child: stack,
      ),
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
        popup.hiding
            ? (popup.fastHiding ? Curves.linear : Curves.easeInCirc)
            : Curves.linear;
    final hideDuration =
        popup.hiding
            ? (popup.fastHiding ? _fastHideDuration : _slowHideDuration)
            : _fadeInDuration;
    final colorKey = titleColor.value ^ bodyColor.value;
    if (popup._cachedBodySpan == null || popup._spanColorKey != colorKey) {
      final c = composeNotificationContent(data, settings);
      popup._cachedContent = c;
      popup._cachedBodySpan = _buildBodySpan(c, titleColor, bodyColor);
      popup._spanColorKey = colorKey;
    }
    final content = popup._cachedContent!;
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
                              popup._cachedBodySpan!,
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
          cacheWidth: 124,
          cacheHeight: 124,
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
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 23),
        decoration: BoxDecoration(
          color: accentColor,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: const Text(
          'Reply',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
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
