# notification_manager_native — DBus/native notification manager

- [ ] [CRITICAL] No userpic fallback: if `data.avatarPath.isEmpty` the notification sends no image at all; AyuGram always calls `GenerateUserpic(peer, userpicView)` which produces a colored placeholder even for peers with no custom photo — `notification_manager_native.dart:387` ← `notifications_manager_linux.cpp:675-710`

- [ ] [MAJOR] `_inhibited` read once at init and never refreshed; AyuGram reads `_interface.get_inhibited()` live on every `invokeIfNotInhibited` call, so toggling DND after app start has no effect on sound suppression in the Dart version — `notification_manager_native.dart:160,224-232,146` ← `notifications_manager_linux.cpp:873-877`

- [ ] [MAJOR] `_escapeHtml` does not escape `"` (double-quote); AyuGram uses Qt's `toHtmlEscaped()` which also escapes `"`, so messages containing `"` in body-markup mode produce malformed HTML — `notification_manager_native.dart:462-467` ← `notifications_manager_linux.cpp:779-792`

- [ ] [MAJOR] No GNotification/Flatpak fallback: AyuGram has a complete `Gio::Notification` code path (`UseGNotification()`) for Flatpak sandboxes and systems with a GApplication; Dart only implements the raw FDO DBus path and silently fails for sandboxed installs — `notification_manager_native.dart:170-173` ← `notifications_manager_linux.cpp:134-144,537-728`

- [ ] [MAJOR] No DBus service-restart watcher: AyuGram registers a static `ServiceWatcher` that calls `createManager()` when the notification daemon ownership changes; if the daemon crashes and restarts the Dart manager stays broken with a stale `_notifProxy` — `notification_manager_native.dart:175` ← `notifications_manager_linux.cpp:63-96,239-241`

- [ ] [MAJOR] `desktop-entry` hint hardcoded as `'uniclient'`; AyuGram uses `QGuiApplication::desktopFileName()` so the notification is always associated with the correct `.desktop` file regardless of install path — `notification_manager_native.dart:383-384` ← `notifications_manager_linux.cpp:670-671`

- [ ] [MAJOR] `_buildImageHint` re-decodes and re-resizes the PNG that `CachedUserpics.get()` already wrote as 64×64; the file is read from disk, decoded, then `copyResize(image, width: 64, height: 64)` is called on an image that is already 64×64, wasting one full decode+resize cycle per notification — `notification_manager_native.dart:469-506` vs `notification_manager_native.dart:79`

- [ ] [MAJOR] Default `_imageDataKey` is `'image-data'` but AyuGram's `GetImageKey()` defaults to `"icon_data"` when `CurrentServerInformation` is empty (i.e. `GetServerInformation` fails); on old notification daemons where the call fails the Dart will send the wrong key and the image will be silently ignored — `notification_manager_native.dart:161` ← `notifications_manager_linux.cpp:124-132`
