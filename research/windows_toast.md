# Windows native toast notifications — pure-Go ABI research (2026-09-14)

Status: RESEARCHED, not implemented. Next slice picks this up.
Primary sources (fetched fresh, not trusted from stale notes):
- mingw-w64 `windows.ui.notifications.h` (interface UUIDs + vtable order)
- mingw-w64 `windows.data.xml.dom.h`
- valinet's pure-C toast gist (activation-flow reference):
  https://gist.github.com/valinet/3283c79ba35fc8f103c747c8adbb6b23

## Goal
Gap 5 of the parity remaining-gaps list: the Windows native
notification transport (Linux DBus is wire-verified; windows/wasm/
android remain). Pure-Go COM/WinRT via syscalls — the repo already has
the pattern: gui/taskbar_windows.go (ITaskbarList3, CoInitializeEx +
CoCreateInstance + pinned vtable slots).

## Activation flow (from the pure-C reference)
1. `WindowsCreateString` / `WindowsDeleteString` — winstring.dll
   (HSTRINGs for class names, the XML payload, the AUMID).
2. `RoGetActivationFactory(hsClass, IID, &factory)` — combase.dll.
3. Manager: class "Windows.UI.Notifications.ToastNotificationManager",
   factory IID IToastNotificationManagerStatics →
   `CreateToastNotifierWithId(hsAUMID, &notifier)` (slot 7).
4. XmlDocument: `RoActivateInstance(hsXmlDocument, &inspectable)`
   (combase.dll) → QI IXmlDocument → QI IXmlDocumentIO →
   `LoadXml(hsXml)` (slot 6).
5. Notification: factory IID IToastNotificationFactory on class
   "Windows.UI.Notifications.ToastNotification" →
   `CreateToastNotification(pXmlDocument, &toast)` (slot 6).
6. `notifier->Show(toast)` (slot 6 of IToastNotifier).

## Interface UUIDs + vtable slots (IUnknown 0-2, IInspectable 3-5)
- IToastNotificationManagerStatics
  {50ac103f-d235-4598-bbef-98fe4d1a3ad4}: CreateToastNotifier=6,
  CreateToastNotifierWithId=7, GetTemplateContent=8
- IToastNotifier {75927b93-03f3-41ec-91d3-6e5bac1b38e7}:
  Show=6, Hide=7, get_Setting=8
- IToastNotificationFactory {04124b20-82c6-4229-b109-fd9ed4662b53}:
  CreateToastNotification=6
- IToastNotification {997e2675-059e-4e60-8b06-1760917c8b80}
  (events + properties — not needed for Show-only v1)
- IXmlDocument {f7f3a506-1e87-42d6-bcfb-b8c809fa5494}
- IXmlDocumentIO {6cd0e74e-ee65-4489-9ebf-ca43e87ba637}:
  LoadXml=6, LoadXmlWithSettings=7, SaveToFileAsync=8
- RoGetActivationFactory/RoActivateInstance: combase.dll;
  WindowsCreateString/WindowsCreateStringReference/WindowsDeleteString:
  winstring.dll.

## Toast XML (v1 shape — title + body text, tdesktop-like)
```xml
<toast scenario="default" duration="short">
  <visual><binding template="ToastGeneric">
    <text><![CDATA[<sender>]]></text>
    <text><![CDATA[<message>]]></text>
  </binding></visual>
</toast>
```

## AUMID (AppUserModelID) — the honest problem
Toasts render only for AUMIDs registered via a Start-Menu shortcut
(IShellLink COM — a separate, bigger slice). Options:
1. PowerShell's AUMID (works on every stock Win10/11, shows
   "Windows PowerShell" as the source — the BurntToast/go-toast
   default; honest but mislabeled source).
2. Register our own shortcut (IShellLink + IPropertyStore COM +
   System.AppUserModel.ID property) — the tdesktop-faithful path,
   ~2x the COM surface.
Decision for v1: option 1 (documented in code + settings as "via
PowerShell's notification registration"), option 2 as the follow-up.

## Wiring point
The Linux DBus transport lives in the notify layer (slice 141's
freedesktop banners + notify.go's notifyOpenAction hop — banner click →
pendingOpen). The Windows transport mirrors: `notify_windows.go`
(build tag windows) with the same entry signature the Linux transport
has; in-app banners remain the click surface v1 (toast click-through
activation needs the COM activator callback + a window-raise —
follow-up).

## Tests (tests-first when implementing)
- The XML builder + AUMID + title/body escaping: pure, unit-tested on
  all platforms (share a _test.go without the build tag).
- The COM path: compile-checked on windows CI (verify.yml cross-build
  + dispatch), honest failure at runtime (missing combase → banner
  fallback, never a crash).
