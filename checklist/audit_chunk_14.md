# notification_system — Notification scheduling, grouping, and dispatch

- [ ] [CRITICAL] `_scheduleDispatch` creates `Timer` objects that are never stored, so `dispose()` cannot cancel them — pending timers fire after `dispose()` and call `_dispatch()` on an already-cleaned-up system (accessing disposed `_manager`, `_settings`, `_lastAlertPerThread`) — `notification_system.dart:338-348,559-569` ← `notifications_manager.cpp:492-506` (C++ uses `_waiters.clear()` + single cancellable `_waitTimer` so `showNext()` is a no-op after clear)

- [ ] [MAJOR] `_kNotifyCloudDelay` (30 s), `_kNotifyDefaultDelay` (1500 ms), and `onlineCloudTimeoutSec` (300) are hardcoded constants; C++ reads `config.notifyCloudDelay`, `config.notifyDefaultDelay`, and `config.onlineCloudTimeout` from the server-negotiated MTP config — values can differ per server and must come from the engine bridge — `notification_system.dart:99-105,312` ← `notifications_manager.cpp:387-393` + `mtproto_config.h:24-26`

- [ ] [MAJOR] Forward-group body text is hardcoded English (`'${group.length} forwarded messages'`) instead of a localisation call; C++ uses `tr::lng_forward_messages(tr::now, lt_count, fields.forwardedCount)` — `notification_system.dart:421` ← `notifications_manager.cpp:1608-1609`

- [ ] [MAJOR] Album notifications dispatch `group.last` with its per-item media type (Photo/Video/…); C++ replaces the body with `tr::lng_in_dlg_album(tr::now)` whenever `item->groupId()` is set — `notification_system.dart:408-413` ← `notifications_manager.cpp:1610-1611`

- [ ] [MAJOR] `_settingWaiters` is an unbounded `List<NotificationData>` that accumulates every notification whose mute state is unresolved, including multiple entries for the same chat; C++ `_settingWaiters` is a `base::flat_map<Thread*, Waiter>` (one entry per thread, kept only if `timing.when` is earlier than the existing one) so at most one pending item per thread can queue — `notification_system.dart:121,233,488-502` ← `notifications_manager.cpp:473-483`

- [ ] [MAJOR] No `isMessageHidden` guard before scheduling: C++ skips notifications for messages suppressed by AyuGram filters (`AyuState::isHidden` + `FiltersController::filtered`); `NotificationData` has no `isHidden` field and the system never checks for it, so filtered/hidden messages still produce notifications — `notification_system.dart:206-244` ← `notifications_manager.cpp:437-440` + `telegram_helpers.cpp:296-302`
