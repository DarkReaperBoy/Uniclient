import 'dart:async';
import 'dart:collection';

import 'notification_manager.dart';
import 'notification_types.dart';
import 'system_idle.dart';

typedef NotificationTapCallback = void Function(
    String accountId, String chatId);
typedef NotificationDisplayCallback = void Function(
    DefaultNotificationItem item);
typedef NotificationDismissCallback = void Function(String id);
typedef NotificationStartHidingCallback = void Function(String id);
typedef NotificationUpdateDisplayCallback = void Function(
    DefaultNotificationItem item);

class DefaultNotificationItem {
  final String id;
  NotificationData data;
  final DateTime shownAt;
  bool waitingForInput;

  DefaultNotificationItem({
    required this.id,
    required this.data,
    required this.shownAt,
    this.waitingForInput = true,
  });
}

const _dismissDuration = Duration(milliseconds: 3000);
const _inputCheckInterval = Duration(milliseconds: 300);

class DefaultManager extends NotificationManager {
  @override
  ManagerType get type => ManagerType.defaultPopup;

  final List<DefaultNotificationItem> _active = [];
  final Queue<DefaultNotificationItem> _queue = Queue();
  final Map<String, Timer> _dismissTimers = {};
  Timer? _inputCheckTimer;
  // App-local "last user input" instant — AyuGram's in-app fallback
  // (base::LastUserInputTime()'s Qt event-filter over the app window), fed from
  // main.dart's window-level Listener via onUserInput(). Folded together with
  // the GLOBAL OS idle source (SystemIdle) in _effectiveLastInput(), mirroring
  // Core::App().lastNonIdleTime() == max(Platform::LastUserInputTime, app-local).
  DateTime _lastUserInputTime = DateTime.now();
  int _nextId = 0;
  int _maxVisible = 3;
  NotificationCorner _corner = NotificationCorner.bottomRight;

  NotificationTapCallback? onTap;
  NotificationDisplayCallback? onShow;
  NotificationDismissCallback? onDismiss;
  NotificationStartHidingCallback? onStartHiding;
  NotificationStartHidingCallback? onStartHidingFast;
  NotificationUpdateDisplayCallback? onUpdateDisplay;
  VoidCallbackNoArgs? onHideAllChanged;
  VoidCallbackNoArgs? onStartHidingHideAll;
  VoidCallbackNoArgs? onStartHidingHideAllFast;
  VoidCallbackNoArgs? onStopHidingHideAll;
  VoidCallbackNoArgs? onCornerChanged;
  bool Function(String id)? isStickyCheck;

  List<DefaultNotificationItem> get activeNotifications =>
      List.unmodifiable(_active);

  bool get hasQueue => _queue.isNotEmpty;

  bool get showHideAll => _active.length >= 2 || _queue.isNotEmpty;

  NotificationCorner get corner => _corner;

  void onUserInput() {
    _lastUserInputTime = DateTime.now();
  }

  /// Effective "last user input" instant — the later of the GLOBAL OS idle
  /// source (SystemIdle, the mirror of base::Platform::LastUserInputTime()) and
  /// the app-local pointer signal, exactly like AyuGram's
  /// Core::App().lastNonIdleTime() == std::max(Platform::LastUserInputTime(),
  /// _lastNonIdleTime) (notifications_manager_default.cpp:189-191 →
  /// application.cpp:1283-1287). The app-local time is always available on
  /// native desktop, so this never returns null there — when no OS idle source
  /// exists we still gate on real pointer activity rather than dismissing at
  /// once.
  DateTime _effectiveLastInput() {
    final global = SystemIdle.lastInputTime();
    if (global == null) return _lastUserInputTime;
    return global.isAfter(_lastUserInputTime) ? global : _lastUserInputTime;
  }

  @override
  void showNotification(NotificationData data, NotificationSettings settings) {
    _maxVisible = settings.maxNotificationCount.clamp(1, 5);
    _corner = settings.corner;

    final item = DefaultNotificationItem(
      id: 'notif_${_nextId++}',
      data: data,
      shownAt: DateTime.now(),
    );

    if (_active.length >= _maxVisible) {
      _queue.addLast(item);
      onHideAllChanged?.call();
      return;
    }

    _displayItem(item);
  }

  void _displayItem(DefaultNotificationItem item) {
    _active.add(item);
    onShow?.call(item);
    onHideAllChanged?.call();
    _checkLastInput();
  }

  // Faithful port of Manager::checkLastInput (notifications_manager_default.cpp
  // :186-200) + Notification::checkLastInput (:767-785). Each waiting popup is
  // gated on the GLOBAL last-input time: while the last user input is at/before
  // when the popup appeared (user idle / away from the machine) it keeps
  // waiting on screen; only once there is input AFTER it appeared (user active
  // again) does the notifyWaitLongHide (3 s) auto-dismiss countdown start.
  // WaitForInputForCustom() is true on every desktop platform, so the wait is
  // always armed. Re-polls every 300 ms while any popup is still waiting
  // (AyuGram's _inputCheckTimer.callOnce(300)).
  void _checkLastInput() {
    final hasReplying =
        _active.any((n) => isStickyCheck != null && isStickyCheck!(n.id));
    final lastInput = _effectiveLastInput();

    var anyWaiting = false;
    for (final item in _active) {
      if (!item.waitingForInput) continue;
      // waitForUserInput == (lastInput <= shownAt): no input since it appeared.
      if (lastInput.isAfter(item.shownAt)) {
        item.waitingForInput = false;
        if (!hasReplying) {
          _startDismissTimer(item.id);
        }
      } else {
        anyWaiting = true;
      }
    }

    if (anyWaiting) {
      _inputCheckTimer?.cancel();
      _inputCheckTimer = Timer(_inputCheckInterval, _checkLastInput);
    }
  }

  void _startDismissTimer(String id) {
    _dismissTimers[id]?.cancel();
    _dismissTimers[id] = Timer(_dismissDuration, () {
      _dismissTimers.remove(id);
      onStartHiding?.call(id);
    });
  }

  void dismiss(String id) {
    _dismissTimers[id]?.cancel();
    _dismissTimers.remove(id);
    _active.removeWhere((n) => n.id == id);
    onDismiss?.call(id);

    if (_queue.isNotEmpty && _active.length < _maxVisible) {
      _displayItem(_queue.removeFirst());
    }
    onHideAllChanged?.call();
  }

  void startAllHiding() {
    final hasReplying =
        _active.any((n) => isStickyCheck != null && isStickyCheck!(n.id));
    if (hasReplying) return;
    // Hover-leave begins the slow fade IMMEDIATELY — AyuGram's startAllHiding()
    // calls notification->startHiding() → hideSlow(), which animates opacity
    // 1→0 at once (no extra dismiss delay). Cancel any pending dismiss timer so
    // it cannot double-fire, then start the fade now.
    // (notifications_manager_default.cpp:202-211, startHiding/hideSlow :1238,:554)
    for (final item in _active) {
      _dismissTimers[item.id]?.cancel();
      _dismissTimers.remove(item.id);
      onStartHiding?.call(item.id);
    }
    // The HideAll button fades out together with the notification rows when the
    // cursor leaves the stack, but only while fewer than two notifications are
    // still queued — matching AyuGram's
    //   if (_hideAll && _queuedNotifications.size() < 2) _hideAll->startHiding();
    // (notifications_manager_default.cpp:207-209).
    if (showHideAll && _queue.length < 2) {
      onStartHidingHideAll?.call();
    }
  }

  void stopAllHiding() {
    for (final t in _dismissTimers.values) {
      t.cancel();
    }
    _dismissTimers.clear();
    // Restore the HideAll button to full opacity when the cursor re-enters —
    // matching AyuGram's
    //   if (_hideAll) _hideAll->stopHiding();
    // (notifications_manager_default.cpp:217-219).
    if (showHideAll) {
      onStopHidingHideAll?.call();
    }
  }

  void hideAll() {
    for (final t in _dismissTimers.values) {
      t.cancel();
    }
    _dismissTimers.clear();
    final ids = _active.map((n) => n.id).toList();
    _active.clear();
    _queue.clear();
    // AyuGram's doClearAll() unlinks every notification → hideFast(): a smooth
    // 150ms (notifyFastAnim) fade to transparent, NOT an abrupt removal at full
    // opacity. Drive the popup's FAST-hide channel for the rows and the HideAll
    // button so they fade out together.
    // (notifications_manager_default.cpp:375-381, unlinkHistory→hideFast :1202,:570)
    for (final id in ids) {
      onStartHidingFast?.call(id);
    }
    onStartHidingHideAllFast?.call();
    // Fallback for when no popup view is mounted to self-remove on fade-end:
    // force-dismiss after the fast-hide animation would have completed.
    Timer(const Duration(milliseconds: 150), () {
      for (final id in ids) {
        onDismiss?.call(id);
      }
    });
    onHideAllChanged?.call();
  }

  // Shared clear path for the five engine-driven scope clears
  // (chat/item/topic/sublist/account), mirroring AyuGram's doClearFrom* order:
  //   1. Erase the matching QUEUE entries FIRST — so a queued notification for
  //      the very scope being cleared can never be promoted into a freed slot
  //      by the showNextFromQueue() that follows. (The old code ran a per-item
  //      dismiss() loop BEFORE filtering the queue, and dismiss() promotes the
  //      next queued item of ANY scope mid-loop, so a same-scope queued item
  //      got promoted, shown, and then SURVIVED the late queue filter.)
  //   2. Unlink each matching active notification → hideFast(): a smooth 150ms
  //      (notifyFastAnim) fade via the popup's FAST-hide channel, NOT the abrupt
  //      full-opacity teardown the old dismiss()->onDismiss path produced. This
  //      is also the tap path (notification tap → clearForChat), so opening a
  //      chat now fades its notifications instead of snapping them away.
  //   3. showNextFromQueue(): refill the freed slots from the already-filtered
  //      queue right away — AyuGram counts the fading/unlinked notifications as
  //      free, so replacements appear immediately while the cleared rows fade.
  // (notifications_manager_default.cpp:425-455 doClearFrom{History,Session,
  //  Topic,Sublist} + :457-472 doClearFromItem; unlinkHistory->hideFast
  //  :1193-1208,:570-572; showNextFromQueue :222-267)
  void _clearScoped(bool Function(NotificationData data) matches) {
    _queue.removeWhere((n) => matches(n.data));

    final cleared =
        _active.where((n) => matches(n.data)).map((n) => n.id).toList();
    if (cleared.isEmpty) {
      onHideAllChanged?.call();
      return;
    }
    for (final id in cleared) {
      _dismissTimers[id]?.cancel();
      _dismissTimers.remove(id);
      // Remove from the live set immediately (so it stops counting toward
      // _maxVisible, exactly like AyuGram's isUnlinked() notifications) and
      // drive the 150ms fast fade. The popup view self-removes when the
      // animation ends and calls back dismiss() — a safe no-op once the item is
      // gone from _active and the queue is filtered/full. With no view mounted
      // to animate, fall back to an immediate removal so it can't get stuck.
      _active.removeWhere((n) => n.id == id);
      if (onStartHidingFast != null) {
        onStartHidingFast!(id);
      } else {
        onDismiss?.call(id);
      }
    }
    while (_queue.isNotEmpty && _active.length < _maxVisible) {
      _displayItem(_queue.removeFirst());
    }
    onHideAllChanged?.call();
  }

  @override
  void clearForChat(String accountId, String chatId) {
    _clearScoped((d) => d.accountId == accountId && d.chatId == chatId);
  }

  @override
  void clearForItem(String accountId, String chatId, String messageId) {
    _clearScoped((d) =>
        d.accountId == accountId &&
        d.chatId == chatId &&
        d.messageId == messageId);
  }

  @override
  void clearForTopic(String accountId, String chatId, String topicRootId) {
    _clearScoped((d) =>
        d.accountId == accountId &&
        d.chatId == chatId &&
        d.isForumTopic &&
        d.topicRootId == topicRootId);
  }

  @override
  void clearForSublist(String accountId, String chatId, String sublistPeerId) {
    _clearScoped((d) =>
        d.accountId == accountId &&
        d.chatId == chatId &&
        d.isMonoforumSublist &&
        d.sublistPeerId == sublistPeerId);
  }

  @override
  void clearForAccount(String accountId) {
    _clearScoped((d) => d.accountId == accountId);
  }

  @override
  void updateAll() {
    for (final item in _active) {
      onUpdateDisplay?.call(item);
    }
  }

  void updateAvatar(String notifId, String newPath) {
    final item = _active.where((n) => n.id == notifId).firstOrNull;
    if (item == null) return;
    item.data = item.data.copyWith(avatarPath: newPath);
    onUpdateDisplay?.call(item);
  }

  void updateAvatarForPeer(String accountId, String chatId, String newPath) {
    // Only repaint when a real (non-empty) userpic just became available and it
    // actually differs — mirrors AyuGram's updatePeerPhoto() guarding on
    // PeerUserpicLoading / _userpicLoaded so it repaints once the download
    // finishes (notifications_manager_default.cpp:1052-1079).
    if (newPath.isEmpty) return;
    for (final item in _active) {
      if (item.data.accountId == accountId &&
          item.data.chatId == chatId &&
          item.data.avatarPath != newPath) {
        item.data = item.data.copyWith(avatarPath: newPath);
        onUpdateDisplay?.call(item);
      }
    }
  }

  @override
  void clearAll() => hideAll();

  @override
  void clearAllFast() {
    for (final t in _dismissTimers.values) {
      t.cancel();
    }
    _dismissTimers.clear();
    _inputCheckTimer?.cancel();
    final ids = _active.map((n) => n.id).toList();
    _active.clear();
    _queue.clear();
    for (final id in ids) {
      onDismiss?.call(id);
    }
    onHideAllChanged?.call();
  }

  @override
  void updateSettings(NotificationSettings settings) {
    final cornerChanged = _corner != settings.corner;
    _maxVisible = settings.maxNotificationCount.clamp(1, 5);
    _corner = settings.corner;
    // NOTE: AyuGram's settingsChanged() also handles ChangeType::DemoIsShown/
    // DemoIsHidden here, animating _demoMasterOpacity → demoMasterOpacityCallback()
    // to dim every live notification + the HideAll button while the position
    // sample is on screen (notifications_manager_default.cpp:162-184). In this
    // codebase that master opacity is a pure VIEW concern, applied in
    // NotificationPopupOverlay via its `demoDimmed` prop (driven by
    // AppState.notifDemoShown), so it is intentionally not re-handled in this
    // controller's settings path.

    // MaxCount change: evict the over-limit notifications through the FAST-hide
    // channel (150ms / notifyFastAnim fade), NOT the abrupt full-opacity
    // dismiss()->onDismiss teardown. AyuGram's settingsChanged(MaxCount) calls
    // unlinkHistory() on each excess, which routes through hideFast()
    // (notifications_manager_default.cpp:148-156; unlinkHistory->hideFast
    // :1202,:570). Evict OLDEST first (_active.first), matching AyuGram keeping
    // the newest notificationsCount(). Remove from the live set immediately so
    // it stops counting toward _maxVisible (like AyuGram's isUnlinked()); the
    // popup view self-removes on fade-end and calls back dismiss() — a safe
    // no-op once it is gone from _active. With no view mounted to animate, fall
    // back to an immediate onDismiss so it can't get stuck. (Mirrors the
    // _clearScoped fast-fade path :247-262, instead of the snap-away dismiss().)
    while (_active.length > _maxVisible) {
      final excess = _active.first;
      _dismissTimers[excess.id]?.cancel();
      _dismissTimers.remove(excess.id);
      _active.removeAt(0);
      if (onStartHidingFast != null) {
        onStartHidingFast!(excess.id);
      } else {
        onDismiss?.call(excess.id);
      }
    }

    while (_queue.isNotEmpty && _active.length < _maxVisible) {
      _displayItem(_queue.removeFirst());
    }

    // Corner change: AyuGram's settingsChanged(Corner) immediately repositions
    // every live notification AND the HideAll button via updatePosition
    // (notifications_manager_default.cpp:139-148). Fire a reposition signal so
    // the view recomputes every popup's slot + the HideAll button for the new
    // corner — without this, popups already on screen stay stuck in the old
    // corner until the next show/dismiss. Fired after the eviction/promotion so
    // it reflects the final live set.
    if (cornerChanged) {
      onCornerChanged?.call();
    }
    onHideAllChanged?.call();
  }

  @override
  void dispose() {
    _inputCheckTimer?.cancel();
    for (final t in _dismissTimers.values) {
      t.cancel();
    }
    _dismissTimers.clear();
    _active.clear();
    _queue.clear();
  }
}

typedef VoidCallbackNoArgs = void Function();
