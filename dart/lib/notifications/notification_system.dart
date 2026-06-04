import 'dart:async';

import '../l10n/strings.dart';
import '../utils/debug.dart';
import 'notification_manager.dart';
import 'notification_manager_default.dart';
import 'notification_manager_native.dart';
import 'notification_sound.dart';
import 'notification_types.dart';

export 'notification_types.dart';
export 'notification_manager.dart';
export 'notification_manager_default.dart';
export 'notification_manager_native.dart';
export 'notification_sound.dart';

enum _ItemNotificationType { message, reaction, pollVote }

class _NotificationKey {
  final String messageId;
  final _ItemNotificationType type;

  const _NotificationKey(this.messageId, this.type);

  @override
  bool operator ==(Object other) =>
      other is _NotificationKey &&
      other.messageId == messageId &&
      other.type == type;

  @override
  int get hashCode => Object.hash(messageId, type);
}

class _AlertRecord {
  DateTime time;
  String ringtonePath;
  _AlertRecord({required this.time, this.ringtonePath = ''});
}

class _AccountSessionState {
  bool isOnline = true;
  int otherOnlineAt = 0;
  int lastSetOnlineAt = 0;
}

class NotificationSystem {
  NotificationManager _manager = DummyManager();
  NotificationSettings _settings = const NotificationSettings();
  final NotificationSoundPlayer _soundPlayer = NotificationSoundPlayer();

  bool _passcodeLocked = false;
  bool get passcodeLocked => _passcodeLocked;
  set passcodeLocked(bool value) => _passcodeLocked = value;

  String _activeAccountId = '';
  String get activeAccountId => _activeAccountId;
  set activeAccountId(String value) => _activeAccountId = value;

  void Function()? onFlashBounce;

  // Live mute-state query: returns null=unknown, true=muted, false=not muted.
  // Matches AyuGram's computeSkipState() pattern for checkDelayed().
  bool? Function(String accountId, String chatId)? onQueryMuteState;

  // Fired whenever the active manager instance is swapped at runtime — most
  // importantly when the native manager's async capability probe discovers the
  // daemon lacks `inline-reply` and we fall back to the custom DefaultManager.
  // The UI re-binds its custom-popup overlay to the new manager so toasts can
  // actually render (the overlay is only mounted when defaultManager != null).
  // Mirrors AyuGram firing `_managerChanged` on every manager swap so the rest
  // of the app can react (window/notifications_manager.cpp:229).
  void Function()? onManagerChanged;

  // Live session-online query for the online-aware notification delay
  // (countTiming). [onQuerySessionOnline] returns whether THIS device/session
  // is currently online (active & focused); [onQueryLastSetOnlineMs] returns
  // the epoch-ms when this session last went online. Both are read fresh at
  // dispatch time, matching AyuGram reading `updates.lastWasOnline()` /
  // `updates.lastSetOnline()` live in countTiming
  // (window/notifications_manager.cpp:386-388).
  bool Function()? onQuerySessionOnline;
  int Function()? onQueryLastSetOnlineMs;

  // Refreshes a notification's chat metadata (title/avatar/type/topic) from the
  // live chat cache. Used when a notification parked with `muteStateUnknown`
  // (chat not yet cached) is resolved: its title/avatar were empty placeholders
  // at receive time, so they are re-derived from the now-loaded chat before it
  // is finally shown. Returns the data unchanged if the chat is still unknown.
  NotificationData Function(NotificationData data)? onRefreshChatData;

  static const _kMinimalDelay = Duration(milliseconds: 100);
  static const _kMinimalForwardDelay = Duration(milliseconds: 500);
  static const _kMinimalAlertDelay = Duration(milliseconds: 500);
  static const _kWaitingForAllGroupedDelay = Duration(milliseconds: 1000);
  static const _kReactionNotificationEach = Duration(hours: 1);
  Duration _cloudDelay = const Duration(seconds: 30);
  Duration _defaultDelay = const Duration(milliseconds: 1500);
  int _onlineCloudTimeoutSec = 300;

  // §37.6.3 dedup: threadKey → { (messageId, type) → lastTime }
  final Map<String, Map<_NotificationKey, DateTime>> _whenMaps = {};

  // §37.6.1 sound/flash alert cooldown per thread, with per-chat ringtone
  final Map<String, _AlertRecord> _lastAlertPerThread = {};

  // §37.6.2 forward/album grouping buffer
  Timer? _groupedTimer;
  final List<NotificationData> _groupedBuffer = [];

  // Pending dispatch timers keyed by chatKey for per-chat cancellation
  final Map<String, List<Timer>> _pendingTimers = {};

  // Per-account session state for cross-device dedup
  final Map<String, _AccountSessionState> _accountStates = {};

  // Notifications waiting for mute state resolution, keyed by thread key.
  // Each thread holds the FULL queue of pending notifications so that every
  // message arriving during the unknown-mute window is dispatched once the
  // state resolves — C++ keeps the queue on the Thread object and showNext()
  // walks it, dispatching all N (notifications_manager.cpp:473-482, 699+).
  final Map<String, List<NotificationData>> _settingWaiters = {};

  NotificationManager get manager => _manager;
  ManagerType get activeManagerType => _manager.type;
  NotificationSettings get settings => _settings;

  DefaultManager? get defaultManager =>
      _manager is DefaultManager ? _manager as DefaultManager : null;

  NativeManager? get nativeManager =>
      _manager is NativeManager ? _manager as NativeManager : null;

  NotificationSoundPlayer get soundPlayer => _soundPlayer;

  void init(NotificationSettings settings) {
    _settings = settings;
    // Re-push the sound-file hint to the native manager once the bundled default
    // sound finishes its async first-launch extraction — `defaultSoundPath` is
    // empty until then, so the initial _syncNativeSoundPath() below can't see it.
    _soundPlayer.onDefaultSoundReady = _syncNativeSoundPath;
    _soundPlayer.init();
    _selectManager();
    _syncNativeSoundPath();
    Debug.log('NOTIF', 'system init, manager=${_manager.type}');
  }

  void updateSettings(NotificationSettings settings) {
    final oldSettings = _settings;
    final oldType = _manager.type;
    _settings = settings;
    _selectManager();
    _manager.updateSettings(settings);
    if (oldType != _manager.type) {
      Debug.log(
          'NOTIF', 'manager switched: $oldType → ${_manager.type}');
    }
    // AyuGram's System ctor couples settingsChanged → clearAll/updateAll
    // (notifications_manager.cpp:206-216). A DesktopEnabled change (here the
    // `desktopNotify` flag flipping, fired only on actual change in AyuGram's
    // settings UI, settings_notifications.cpp:1065-1069) clears every on-screen
    // popup so disabling desktop notifications doesn't leave lingering toasts.
    // A ViewParams change (AyuGram's `notifyView`, decomposed Dart-side into
    // previewName/previewText) calls updateAll() so already-shown notifications
    // refresh their name/text preview live.
    if (oldSettings.desktopNotify != settings.desktopNotify) {
      clearAll();
    }
    if (oldSettings.previewName != settings.previewName ||
        oldSettings.previewText != settings.previewText) {
      updateAll();
    }
  }

  void updateAll() {
    _manager.updateAll();
  }

  /// Repaint on-screen custom-popup notifications for a peer once its userpic
  /// finishes downloading. The native manager bakes the avatar into the DBus
  /// image at show time and cannot update a live notification's icon, so this
  /// targets the DefaultManager only — matching AyuGram's `updatePeerPhoto`
  /// living in the custom Default manager.
  void updateAvatarForPeer(String accountId, String chatId, String avatarPath) {
    defaultManager?.updateAvatarForPeer(accountId, chatId, avatarPath);
  }

  void setServerConfig({
    int? cloudDelayMs,
    int? defaultDelayMs,
    int? onlineCloudTimeoutSec,
  }) {
    if (cloudDelayMs != null) _cloudDelay = Duration(milliseconds: cloudDelayMs);
    if (defaultDelayMs != null) _defaultDelay = Duration(milliseconds: defaultDelayMs);
    if (onlineCloudTimeoutSec != null) _onlineCloudTimeoutSec = onlineCloudTimeoutSec;
  }

  void updateSessionState({
    required String accountId,
    required bool isOnline,
    int otherOnlineAt = 0,
    int lastSetOnlineAt = 0,
  }) {
    final state =
        _accountStates.putIfAbsent(accountId, () => _AccountSessionState());
    state.isOnline = isOnline;
    state.otherOnlineAt = otherOnlineAt;
    state.lastSetOnlineAt = lastSetOnlineAt;
  }

  void _selectManager() {
    final wantNative =
        _settings.useNativeNotifications && !_settings.forceCustomNotifications;

    ManagerType targetType;
    if (wantNative && nativeNotificationsSupported()) {
      targetType = ManagerType.native;
    } else {
      targetType = ManagerType.defaultPopup;
    }

    if (_manager.type == targetType) return;

    _manager.dispose();
    switch (targetType) {
      case ManagerType.native:
        _manager = NativeManager(onInitComplete: () {
          final nm = nativeManager;
          if (nm != null && !nm.byDefault) {
            Debug.log('NOTIF',
                'Daemon lacks required capabilities, falling back to custom');
            nm.dispose();
            _manager = DefaultManager();
            _manager.updateSettings(_settings);
            // Notify the UI so it mounts/re-binds the custom-popup overlay to
            // this new DefaultManager — without this the overlay stays unbound
            // (it was never created while native was active) and the manager
            // stores items that nothing ever renders.
            onManagerChanged?.call();
          }
        });
      case ManagerType.defaultPopup:
        _manager = DefaultManager();
      case ManagerType.dummy:
        _manager = DummyManager();
    }
    _syncNativeSoundPath();
  }

  void _syncNativeSoundPath() {
    final nm = nativeManager;
    if (nm != null) {
      nm.defaultSoundPath = _soundPlayer.defaultSoundPath ?? '';
    }
  }

  void onNewMessage(NotificationData data) {
    // desktopNotify is intentionally NOT gated here. AyuGram registers the
    // sound/flash alert (`_whenAlerts`) with NO desktopNotify gate — only the
    // visual toast is gated (notifications_manager.cpp:454 alert vs :464 toast;
    // showNext fires alerts before the `!desktopNotify()` early-return at
    // :782-789). So with desktop popups off but "Play sound"/"Flash taskbar"
    // on, the alert still plays/flashes — these are independent settings. The
    // toast itself is gated below in _dispatch.
    if (data.isHidden) return;
    if (data.isOutgoing && !data.isScheduled) return;

    // The per-type filter (channels/groups/private) needs the chat type, which
    // is unknown until the chat is cached. When mute state is unknown, apply
    // only the account filter now and defer the per-type decision to
    // checkDelayed (re-evaluated once the chat — and its type — loads).
    if (data.muteStateUnknown) {
      if (!_settings.notifyFromAll && data.accountId != _activeAccountId) return;
    } else if (!_shouldNotifyForType(data)) {
      return;
    }

    // §37.7: Muted chat handling. A muted chat is silenced UNLESS the message
    // personally mentions me and the mention sender isn't individually muted —
    // AyuGram's notifyBy = specialNotificationPeer() bypass.
    var effectiveData = data;
    if (data.isMuted) {
      if (data.isScheduled && data.isOutgoing) {
        effectiveData = data.copyWith(isSilent: true);
      } else if (data.mentionsMe && !data.isSenderMuted) {
        // Mention from a non-muted sender pierces the muted chat: show with sound.
      } else {
        return;
      }
    }

    // §37.7: Force silent for reactions/poll votes
    if (effectiveData.isReaction || effectiveData.isPollVote) {
      effectiveData = effectiveData.copyWith(isSilent: true);
    }

    if (!_passesDedup(effectiveData)) return;

    // Buffer notifications with unknown mute state for later processing.
    // Queue ALL of them per thread — not just the first — so none are lost
    // when the state resolves (C++ keeps the full queue on the Thread).
    if (effectiveData.muteStateUnknown) {
      _settingWaiters
          .putIfAbsent(_threadKey(effectiveData), () => [])
          .add(effectiveData);
      return;
    }

    if (_isGroupable(effectiveData)) {
      _addToGroupBuffer(effectiveData);
      return;
    }

    final delay = _countTiming(effectiveData);
    _scheduleDispatch(effectiveData, delay);
  }

  bool _shouldNotifyForType(NotificationData data) {
    // C++: `!notifyFromAll() && &thread->session().account() != domain().active()`
    // (notifications_manager.cpp:342-345). No "skip if unset" fallback — the
    // active account is always known (wired from AppState in main.dart), so the
    // filter genuinely silences other accounts instead of being a no-op.
    if (!_settings.notifyFromAll && data.accountId != _activeAccountId) {
      return false;
    }
    if (data.isReaction || data.isPollVote) return _settings.reactionsNotify;
    if (data.isChannel) return _settings.channelsNotify;
    if (data.isGroup) return _settings.groupsNotify;
    return _settings.privateChatsNotify;
  }

  // Thread key — uniquely identifies a (peer, topic/sublist) the way C++ keys
  // _whenMaps/_whenAlerts/_settingWaiters by not_null<Data::Thread*>. A topic
  // or monoforum sublist is a DISTINCT key from the parent chat, so per-topic
  // clears never collide with another topic's dedup/alert state
  // (notifications_manager.cpp:212-215, 468, 508-540).
  String _threadKey(NotificationData data) => _threadKeyOf(
      data.accountId, data.chatId, data.topicRootId, data.sublistPeerId);

  String _threadKeyOf(
      String accountId, String chatId, String topicRootId, String sublistPeerId) {
    if (topicRootId.isNotEmpty) return '$accountId:$chatId:t:$topicRootId';
    if (sublistPeerId.isNotEmpty) return '$accountId:$chatId:s:$sublistPeerId';
    return '$accountId:$chatId';
  }

  // True when [key] is the chat thread itself or one of its topic/sublist
  // sub-threads — used by chat-level clears (≈ C++ clearFromHistory, which
  // matches every thread whose owningHistory() == history). The trailing ':'
  // guard prevents chatId "12" from matching chatId "123".
  bool _keyInChat(String key, String chatKey) =>
      key == chatKey || key.startsWith('$chatKey:');

  _ItemNotificationType _notifType(NotificationData data) {
    if (data.isReaction) return _ItemNotificationType.reaction;
    if (data.isPollVote) return _ItemNotificationType.pollVote;
    return _ItemNotificationType.message;
  }

  bool _passesDedup(NotificationData data) {
    if (data.messageId.isEmpty) return true;

    final threadKey = _threadKey(data);
    final key = _NotificationKey(data.messageId, _notifType(data));
    final now = DateTime.now();

    final threadMap = _whenMaps.putIfAbsent(threadKey, () => {});
    final lastTime = threadMap[key];

    if (lastTime != null) {
      if (key.type == _ItemNotificationType.reaction ||
          key.type == _ItemNotificationType.pollVote) {
        if (now.difference(lastTime) < _kReactionNotificationEach) {
          return false;
        }
      } else {
        return false;
      }
    }

    threadMap[key] = now;

    if (threadMap.length > 500) {
      final cutoff = now.subtract(const Duration(hours: 2));
      threadMap.removeWhere((_, t) => t.isBefore(cutoff));
    }

    return true;
  }

  bool _isGroupable(NotificationData data) {
    if (data.groupedId.isNotEmpty) return true;
    if (data.forwardFrom.isNotEmpty && data.forwardCount <= 1) return true;
    return false;
  }

  Duration _countTiming(NotificationData data) {
    Duration delay = _kMinimalDelay;

    if (data.forwardFrom.isNotEmpty) {
      if (delay < _kMinimalForwardDelay) delay = _kMinimalForwardDelay;
    }

    if (!_settings.disableNotificationsDelay) {
      final state = _accountStates[data.accountId];
      final otherOnlineAt = state?.otherOnlineAt ?? 0;
      // Only relevant once another device has been seen online (cOtherOnline).
      // With no other session active both branches are inert and the delay
      // stays minimal — exactly AyuGram's behaviour when cOtherOnline()==0.
      if (otherOnlineAt > 0) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final nowSec = nowMs ~/ 1000;
        // Read this session's online state fresh (AyuGram reads
        // updates.lastWasOnline()/lastSetOnline() live in countTiming); fall
        // back to the last snapshot stored via updateSessionState.
        final isOnline =
            onQuerySessionOnline?.call() ?? state?.isOnline ?? true;
        final lastSetOnlineMs =
            onQueryLastSetOnlineMs?.call() ?? state?.lastSetOnlineAt ?? nowMs;
        final otherNotOld = otherOnlineAt + _onlineCloudTimeoutSec > nowSec;
        final otherLaterThanMe =
            otherOnlineAt * 1000 + (nowMs - lastSetOnlineMs) > nowSec * 1000;

        if (!isOnline && otherNotOld && otherLaterThanMe) {
          delay = _cloudDelay;
        } else if (otherOnlineAt >= nowSec) {
          delay = _defaultDelay;
        }
      }
    }

    if (_settings.disableNotificationsDelay) {
      delay = _kMinimalDelay;
      if (data.forwardFrom.isNotEmpty && delay < _kMinimalForwardDelay) {
        delay = _kMinimalForwardDelay;
      }
    }

    return delay;
  }

  void _scheduleDispatch(NotificationData data, Duration delay) {
    if (delay <= Duration.zero) {
      _dispatch(data);
      return;
    }
    final chatKey = _threadKey(data);
    late final Timer timer;
    timer = Timer(delay, () {
      final timers = _pendingTimers[chatKey];
      timers?.remove(timer);
      if (timers != null && timers.isEmpty) _pendingTimers.remove(chatKey);
      _dispatch(data);
    });
    _pendingTimers.putIfAbsent(chatKey, () => []).add(timer);
  }

  bool _isSameGroup(NotificationData a, NotificationData b) {
    if (a.accountId != b.accountId || a.chatId != b.chatId) return false;
    if (a.groupedId.isNotEmpty && b.groupedId.isNotEmpty) {
      return a.groupedId == b.groupedId;
    }
    if (a.forwardFrom.isNotEmpty && b.forwardFrom.isNotEmpty) {
      return a.senderId == b.senderId &&
          (a.timestamp - b.timestamp).abs() <= 2;
    }
    return false;
  }

  void _addToGroupBuffer(NotificationData data) {
    if (_groupedTimer != null && _groupedTimer!.isActive) {
      _groupedTimer!.cancel();
      if (_groupedBuffer.isNotEmpty && !_isSameGroup(_groupedBuffer.last, data)) {
        _flushGroupedBuffer();
      }
    }
    _groupedBuffer.add(data);
    _groupedTimer =
        Timer(_kWaitingForAllGroupedDelay, _flushGroupedBuffer);
  }

  void _flushGroupedBuffer() {
    if (_groupedBuffer.isEmpty) return;

    final byChat = <String, List<NotificationData>>{};
    for (final n in _groupedBuffer) {
      byChat.putIfAbsent(_threadKey(n), () => []).add(n);
    }
    _groupedBuffer.clear();

    for (final items in byChat.values) {
      final albumGroups = <String, List<NotificationData>>{};
      final forwardGroups = <String, List<NotificationData>>{};
      final ungrouped = <NotificationData>[];

      for (final n in items) {
        if (n.groupedId.isNotEmpty) {
          albumGroups.putIfAbsent(n.groupedId, () => []).add(n);
        } else if (n.forwardFrom.isNotEmpty && n.forwardCount <= 1) {
          final fwdKey = n.senderId;
          final existing = forwardGroups[fwdKey];
          if (existing != null &&
              existing.isNotEmpty &&
              (n.timestamp - existing.last.timestamp).abs() <= 2) {
            existing.add(n);
          } else if (existing == null) {
            forwardGroups[fwdKey] = [n];
          } else {
            ungrouped.add(n);
          }
        } else {
          ungrouped.add(n);
        }
      }

      for (final group in albumGroups.values) {
        if (group.length == 1) {
          _dispatch(group.first);
        } else {
          _dispatch(group.last.copyWith(text: TrStrings.lngInDlgAlbum()));
        }
      }

      for (final group in forwardGroups.values) {
        if (group.length == 1) {
          _dispatch(group.first);
        } else {
          // AyuGram advances `groupedItem` to each later forward and shows the
          // LAST (notifications_manager.cpp:901 `groupedItem = nextItem`,
          // displayed via `_lastHistoryItemId = groupedItem->fullId()` at :916/
          // :937), so a tapped "Forwarded N messages" opens at the latest
          // forward — not the earliest — and carries its timestamp/message id.
          // The album branch above already uses .last; match it here.
          _dispatch(group.last.copyWith(
            text: TrStrings.lngForwardMessages(group.length),
            forwardCount: group.length,
          ));
        }
      }

      for (final n in ungrouped) {
        _dispatch(n);
      }
    }
  }

  void _dispatch(NotificationData data) {
    // §37.12: Apply privacy levels — passcode-locked forces HideAll
    var effectiveSettings = _settings;
    if (_passcodeLocked) {
      effectiveSettings = _settings.copyWith(
        previewName: false,
        previewText: false,
      );
    }

    // AyuGram's NativeManager::doShowNotification early-returns and shows NO
    // notification when a reaction/poll-vote arrives while the name preview is
    // hidden: `if (reactionFrom && options.hideNameAndPhoto) return;`
    // (notifications_manager.cpp:1563-1565). `reactionFrom` is non-null for BOTH
    // reactions and poll votes (the type is Reaction/PollVote only when a reactor
    // exists), and hideNameAndPhoto == !previewName. effectiveSettings already
    // forces previewName off under a passcode lock (above), so this single guard
    // covers both the previewName-off setting and the locked case. Without it a
    // reaction would leak the message text ("reacted 👍 to «…»") with previewName
    // off, or surface "reacted 👍 to your message" with title "UniClient" under
    // lock — AyuGram shows nothing in either case. Reactions are already forced
    // silent upstream, so no sound/flash is lost by returning here.
    if ((data.isReaction || data.isPollVote) &&
        !effectiveSettings.previewName) {
      return;
    }

    var effectiveData = data;

    if (!effectiveData.hideMarkAsRead) {
      final hideMessageText = !effectiveSettings.previewText || _passcodeLocked;
      // AyuGram: hideMarkAsRead = hideMessageText || (type != Message) || !item
      //   || ((item->out() || peer->isSelf()) && item->isFromScheduled()).
      // isReaction/isPollVote ARE the (type != Message) cases. The
      // channel/slowmode/stars conditions belong ONLY to hideReplyButton
      // (handled by shouldHideReplyButton) — they must NOT suppress mark-as-read,
      // which AyuGram still shows for channel/slowmode/stars chats (with preview
      // on). messageId.isEmpty mirrors !item; the scheduled clause hides
      // mark-as-read on one's own fired reminders.
      // (notifications_manager.cpp:1093-1096)
      final shouldHide = hideMessageText ||
          effectiveData.isReaction ||
          effectiveData.isPollVote ||
          effectiveData.messageId.isEmpty ||
          ((effectiveData.isOutgoing || effectiveData.isSelf) &&
              effectiveData.isScheduled);
      if (shouldHide) {
        effectiveData = effectiveData.copyWith(hideMarkAsRead: true);
      }
    }

    final content = composeNotificationContent(effectiveData, effectiveSettings);
    final forceHideDetails = !effectiveSettings.previewName && !effectiveSettings.previewText;
    final display = effectiveData.copyWith(
      chatTitle: content.title,
      subtitle: content.subtitle,
      text: content.body,
      avatarPath: forceHideDetails ? '' : effectiveData.avatarPath,
    );

    // DND: DefaultManager (custom toast) is NEVER suppressed by DND on Linux.
    // NativeManager handles DND internally per-call via Inhibited property.
    // Use fresh inhibited value from NativeManager, not stale 30s poll.
    final isNative = _manager is NativeManager;
    final dnd = isNative ? (nativeManager!.inhibited) : false;

    // Only the visual toast is gated by desktopNotify — the sound/flash alert
    // below fires regardless (AyuGram's showNext fires alerts BEFORE the
    // `!desktopNotify()` early-return, notifications_manager.cpp:782-789). For a
    // native daemon that plays the sound itself (handlesSound), the sound rides
    // along inside showNotification and so is correctly suppressed with the
    // toast — mirroring AyuGram's VolumeSupported()==false branch where the
    // daemon owns the sound (notifications_manager_linux.cpp:236).
    if (_settings.desktopNotify) {
      _manager.showNotification(display, effectiveSettings);
    }

    final forceSilent = effectiveData.isSilent || effectiveData.soundNone || (isNative && dnd);

    final threadKey = _threadKey(effectiveData);
    final now = DateTime.now();
    final lastAlert = _lastAlertPerThread[threadKey];
    final alertAllowed =
        lastAlert == null || now.difference(lastAlert.time) >= _kMinimalAlertDelay;

    if (!_manager.handlesSound && alertAllowed && !forceSilent) {
      final chatRingtone = lastAlert?.ringtonePath ?? '';
      final soundPath = effectiveData.soundDocumentPath.isNotEmpty
          ? effectiveData.soundDocumentPath
          : chatRingtone;
      _soundPlayer.play(
        settings: _settings,
        data: soundPath.isNotEmpty
            ? effectiveData.copyWith(soundDocumentPath: soundPath)
            : effectiveData,
      );
      _lastAlertPerThread[threadKey] = _AlertRecord(
        time: now,
        ringtonePath: effectiveData.soundDocumentPath.isNotEmpty
            ? effectiveData.soundDocumentPath
            : (lastAlert?.ringtonePath ?? ''),
      );
    }

    if (_settings.flashBounce && alertAllowed && !forceSilent) {
      onFlashBounce?.call();
    }

    Debug.log('NOTIF',
        'dispatched to ${_manager.type}: ${content.title}'
        '${forceSilent ? " (silent)" : ""}'
        '${dnd ? " (DND)" : ""}'
        '${_passcodeLocked ? " (locked)" : ""}');
  }

  void checkDelayed() {
    if (_settingWaiters.isEmpty) return;

    final query = onQueryMuteState;
    final promoted = <NotificationData>[];
    final emptyKeys = <String>[];

    for (final entry in _settingWaiters.entries) {
      final queue = entry.value;
      final kept = <NotificationData>[];
      // All entries in a thread queue share the same chat, so the live mute
      // state is queried once and reused for the whole queue.
      bool? liveMuted;
      var queried = false;

      for (var data in queue) {
        if (data.muteStateUnknown) {
          if (!queried) {
            liveMuted = query?.call(data.accountId, data.chatId);
            queried = true;
          }
          if (liveMuted == null) {
            kept.add(data); // still unknown (or no resolver) — keep waiting
            continue;
          }
          // Only the mute is resolved here; keep mentionsMe/isSenderMuted so the
          // mention-bypass survives the deferral. Refresh chat metadata too —
          // the data was captured before the chat was in cache, so its
          // title/avatar/type were empty placeholders.
          data = data.copyWith(muteStateUnknown: false, isMuted: liveMuted);
          final refresh = onRefreshChatData;
          if (refresh != null) data = refresh(data);
          // The chat type is known now — apply the per-type filter that was
          // deferred in onNewMessage while the chat was uncached.
          if (!_shouldNotifyForType(data)) continue;
        }
        // Resolved muted with no mention bypass → drop, mirroring the live
        // muted-chat handling in onNewMessage.
        if (data.isMuted && !(data.mentionsMe && !data.isSenderMuted)) {
          continue;
        }
        promoted.add(data);
      }

      if (kept.isEmpty) {
        emptyKeys.add(entry.key);
      } else {
        queue
          ..clear()
          ..addAll(kept);
      }
    }
    for (final key in emptyKeys) {
      _settingWaiters.remove(key);
    }

    for (final data in promoted) {
      if (_isGroupable(data)) {
        _addToGroupBuffer(data);
      } else {
        final delay = _countTiming(data);
        _scheduleDispatch(data, delay);
      }
    }
  }

  void resolveDelayedMuteState({
    required String accountId,
    required String chatId,
    required bool isMuted,
    bool isSenderMuted = true,
    String topicRootId = '',
    String sublistPeerId = '',
  }) {
    final key = _threadKeyOf(accountId, chatId, topicRootId, sublistPeerId);
    final queue = _settingWaiters[key];
    if (queue != null) {
      // Resolve EVERY queued notification for the thread, not just the first.
      for (var i = 0; i < queue.length; i++) {
        queue[i] = queue[i].copyWith(
          muteStateUnknown: false,
          isMuted: isMuted,
          isSenderMuted: isSenderMuted,
        );
      }
    }
    checkDelayed();
  }

  void clearForChat(String accountId, String chatId) {
    _manager.clearForChat(accountId, chatId);
    // Clear the chat thread AND all its topic/sublist sub-threads (≈ C++
    // clearFromHistory → clearForThreadIf(owningHistory() == history)).
    final chatKey = '$accountId:$chatId';
    _whenMaps.removeWhere((k, _) => _keyInChat(k, chatKey));
    _lastAlertPerThread.removeWhere((k, _) => _keyInChat(k, chatKey));
    _settingWaiters.removeWhere((k, _) => _keyInChat(k, chatKey));
    final chatTimers = <Timer>[];
    _pendingTimers.removeWhere((k, timers) {
      if (_keyInChat(k, chatKey)) {
        chatTimers.addAll(timers);
        return true;
      }
      return false;
    });
    for (final t in chatTimers) {
      t.cancel();
    }
    _groupedBuffer.removeWhere(
        (n) => n.accountId == accountId && n.chatId == chatId);
    if (_groupedBuffer.isEmpty) {
      _groupedTimer?.cancel();
      _groupedTimer = null;
    }
  }

  void clearIncomingFromChat(String accountId, String chatId) {
    _manager.clearForChat(accountId, chatId);
    _lastAlertPerThread.remove('$accountId:$chatId');
  }

  void clearIncomingFromTopic(
      String accountId, String chatId, String topicRootId) {
    _manager.clearForTopic(accountId, chatId, topicRootId);
    _lastAlertPerThread.remove(_threadKeyOf(accountId, chatId, topicRootId, ''));
  }

  void clearIncomingFromSublist(
      String accountId, String chatId, String sublistPeerId) {
    _manager.clearForSublist(accountId, chatId, sublistPeerId);
    _lastAlertPerThread
        .remove(_threadKeyOf(accountId, chatId, '', sublistPeerId));
  }

  /// Dismiss the on-screen notification for a single message — called when that
  /// message is deleted or unsent. AyuGram's `System::clearFromItem` is invoked
  /// from `History::destroyMessage` on every message removal and simply forwards
  /// to the active manager without touching scheduling/dedup state
  /// (notifications_manager.cpp:627-631). Fires for ANY chat, not just the
  /// active one (a deleted message in a background chat must still have its
  /// popup pulled).
  void clearFromItem(String accountId, String chatId, String messageId) {
    _manager.clearForItem(accountId, chatId, messageId);
  }

  void clearForAccount(String accountId) {
    _manager.clearForAccount(accountId);
    // C++ clearFromSession → clearForThreadIf cancels the wait timer and drops
    // ALL per-thread state for the session atomically. Mirror that here: leaving
    // _pendingTimers/_settingWaiters/_groupedBuffer/_accountStates dirty would
    // let already-scheduled timers fire AFTER logout and dispatch stale data.
    final prefix = '$accountId:';
    _whenMaps.removeWhere((k, _) => k.startsWith(prefix));
    _lastAlertPerThread.removeWhere((k, _) => k.startsWith(prefix));
    _settingWaiters.removeWhere((k, _) => k.startsWith(prefix));
    final accountTimers = <Timer>[];
    _pendingTimers.removeWhere((k, timers) {
      if (k.startsWith(prefix)) {
        accountTimers.addAll(timers);
        return true;
      }
      return false;
    });
    for (final t in accountTimers) {
      t.cancel();
    }
    _groupedBuffer.removeWhere((n) => n.accountId == accountId);
    if (_groupedBuffer.isEmpty) {
      _groupedTimer?.cancel();
      _groupedTimer = null;
    }
    _accountStates.remove(accountId);
  }

  void clearAll() {
    _manager.clearAll();
    _whenMaps.clear();
    _lastAlertPerThread.clear();
    _settingWaiters.clear();
    for (final timers in _pendingTimers.values) {
      for (final t in timers) {
        t.cancel();
      }
    }
    _pendingTimers.clear();
    _groupedTimer?.cancel();
    _groupedTimer = null;
    _groupedBuffer.clear();
  }

  void dispose() {
    for (final timers in _pendingTimers.values) {
      for (final t in timers) {
        t.cancel();
      }
    }
    _pendingTimers.clear();
    _groupedTimer?.cancel();
    _groupedBuffer.clear();
    _settingWaiters.clear();
    _whenMaps.clear();
    _lastAlertPerThread.clear();
    _accountStates.clear();
    _soundPlayer.dispose();
    _manager.dispose();
  }
}
