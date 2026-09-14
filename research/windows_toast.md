# Windows native toast notifications — pure-Go ABI research (2026-09-14)

Status: SHIPPED. Slice 200 = transport, slice 201 = own AUMID,
slice 202 = click-through activation (this file keeps the primary-source
ABI pins the implementation was built from).
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

## AUMID (AppUserModelID) — shipped as option 2 (slice 201)
`shortcut_windows.go` registers the per-user Start-Menu shortcut via
pure-Go COM, ABI pinned against mingw-w64 headers (fetched this
session, not trusted from notes):
- shobjidl.h: CLSID_ShellLink {00021401-…-46}, IID_IShellLinkW
  {000214F9-…-46}; vtable (after IUnknown 0-2): GetPath 3 …
  SetWorkingDirectory 9 … SetIconLocation 17 … SetPath 20.
- objidl.h: IID_IPersistFile {0000010B-…-46}; Save = slot 6.
- propsys.h: IID_IPropertyStore {886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99};
  SetValue = 6, Commit = 7.
- propkey.h: PKEY_AppUserModel.ID = fmtid
  {9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}, pid 5 — note the tail
  E1-D4-2D-E1-D5-F3 ("E1D42DE4D436" in blog posts is a propagated
  typo). PROPVARIANT VT_LPWSTR = 31, pointer at offset 8 (24-byte
  struct on x64) — layout locked by comabi_test.go on every platform.
Flow: CoCreateInstance → SetPath/SetWorkingDirectory/SetIconLocation →
QI IPropertyStore → SetValue(PKEY_AppUserModel.ID, VT_LPWSTR) →
Commit → QI IPersistFile → Save (property commit BEFORE persist, per
the AppUserModelID docs). PowerShell's AUMID stays the always-works
fallback (resolvedToastAUMID, one attempt per process).

## Click-through — shipped (slice 202)
The WinRT COM activator path needs a separate in-proc DLL (banned,
§1.3 single binary), so activation rides protocol activation instead:
- Toast XML: activationType="protocol" launch="uniclient://open?acc=…
  &chat=…" (attribute-escaped; buildOpenURI/parseOpenURI pure+tested).
- Per-user scheme registration: HKCU\Software\Classes\uniclient
  ("URL Protocol" + shell\open\command `"exe" "%1"`) — x/sys
  registry, no elevation; rewritten at boot so a moved exe self-heals.
- Single-instance channel: <config>/instance.lock ("port cookie",
  atomic rename), localhost TCP listener; a launcher process holding
  the URI forwards "open cookie uri" and exits (HandleLaunchURI before
  engine boot — a click never pays the engine init); the running app
  hops the open through notifyOpenAction (ActionRaise + pendingOpen,
  the same surface as the Linux DBus click). Cold-start clicks boot the
  app and route the URI once an account exists (routeBootURI).

## Tests
- comabi_test.go / openuri_test.go / toastxml_test.go: pure halves
  pinned on every platform (GUID/PKEY values, PROPVARIANT offsets,
  URI round-trips incl. Matrix/IRC ids, XML attribute escaping).
- The COM/registry paths: compile-checked by the windows cross-build
  (verify.yml), honest failure at runtime (error → log-only → the
  in-app banner path, never a crash).
