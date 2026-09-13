//go:build windows

package gui

// notify_windows.go — slice 200: the Windows native notification
// transport (Windows.UI.Notifications toasts, pure-Go WinRT via
// syscalls — the taskbar_windows.go COM pattern extended to Ro*).
// ABI pinned against primary sources (research/windows_toast.md):
// mingw-w64 windows.ui.notifications.h / windows.data.xml.dom.h for the
// interface UUIDs + vtable order (IUnknown 0-2, IInspectable 3-5), and
// valinet's pure-C toast gist for the activation flow.
//
// The AUMID rides PowerShell's Start-Menu registration (works on every
// stock Win10/11 — the go-toast/BurntToast default; the source app row
// shows "Windows PowerShell" until we register our own shortcut, a
// documented follow-up). Click-through activation (the COM activator
// callback + window raise) is also a follow-up: onAction is never
// invoked — the in-app banner remains the click surface, and failures
// fall back to it silently (never a crash, §1.10).

import (
	"sync"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	combaseDLL   = windows.NewLazySystemDLL("combase.dll")
	winstringDLL = windows.NewLazySystemDLL("winstring.dll")

	procRoGetActivationFactory = combaseDLL.NewProc("RoGetActivationFactory")
	procRoActivateInstance     = combaseDLL.NewProc("RoActivateInstance")
	procWindowsCreateString    = winstringDLL.NewProc("WindowsCreateString")
	procWindowsDeleteString    = winstringDLL.NewProc("WindowsDeleteString")
)

// WinRT interface UUIDs (mingw-w64 headers — see file comment).
var (
	iidIToastNotificationManagerStatics = windows.GUID{
		Data1: 0x50AC103F, Data2: 0xD235, Data3: 0x4598,
		Data4: [8]byte{0xBB, 0xEF, 0x98, 0xFE, 0x4D, 0x1A, 0x3A, 0xD4},
	}
	iidIToastNotificationFactory = windows.GUID{
		Data1: 0x04124B20, Data2: 0x82C6, Data3: 0x4229,
		Data4: [8]byte{0xB1, 0x09, 0xFD, 0x9E, 0xD4, 0x66, 0x2B, 0x53},
	}
	iidIToastNotifier = windows.GUID{
		Data1: 0x75927B93, Data2: 0x03F3, Data3: 0x41EC,
		Data4: [8]byte{0x91, 0xD3, 0x6E, 0x5B, 0xAC, 0x1B, 0x38, 0xE7},
	}
	iidIXmlDocument = windows.GUID{
		Data1: 0xF7F3A506, Data2: 0x1E87, Data3: 0x42D6,
		Data4: [8]byte{0xBC, 0xFB, 0xB8, 0xC8, 0x09, 0xFA, 0x54, 0x94},
	}
	iidIXmlDocumentIO = windows.GUID{
		Data1: 0x6CD0E74E, Data2: 0xEE65, Data3: 0x4489,
		Data4: [8]byte{0x9E, 0xBF, 0xCA, 0x43, 0xE8, 0x7B, 0xA6, 0x37},
	}
)

// vtable slot offsets (IUnknown 0-2, IInspectable 3-5, then the
// interface's own methods in declaration order — mingw-w64).
const (
	vtManagerCreateWithId = 7 // CreateToastNotifierWithId(aumid, out)
	vtFactoryCreate       = 6 // CreateToastNotification(xml, out)
	vtNotifierShow        = 6 // Show(toast)
	vtXmlIOLoadXml        = 6 // LoadXml(hstring)
)

// toastAUMID: PowerShell's notification registration (Start Menu
// shortcut) — toasts render only for registered AUMIDs; ours is a
// follow-up (needs IShellLink + IPropertyStore COM).
const toastAUMID = `1AC14E77-02E7-4E5D-B744-2EB1AE5198B7\WindowsPowerShell\v1.0`

var toastMu sync.Mutex

// hstring wraps WindowsCreateString/WindowsDeleteString.
type hstring struct{ h uintptr }

func newHString(s string) (hstring, error) {
	u, err := windows.UTF16FromString(s)
	if err != nil {
		return hstring{}, err
	}
	var hs uintptr
	r, _, _ := procWindowsCreateString.Call(
		uintptr(unsafe.Pointer(&u[0])),
		uintptr(len(u)-1),
		uintptr(unsafe.Pointer(&hs)),
	)
	if r != 0 {
		return hstring{}, syscall.Errno(r)
	}
	return hstring{h: hs}, nil
}

func (h hstring) free() {
	if h.h != 0 {
		procWindowsDeleteString.Call(h.h)
	}
}

// vtableCall fetches slot idx from the interface's vtable.
func vtableCall(itf uintptr, idx int) uintptr {
	lpVtbl := *(*uintptr)(unsafe.Pointer(itf))
	return *(*uintptr)(unsafe.Pointer(lpVtbl + uintptr(idx)*unsafe.Sizeof(uintptr(0))))
}

// comRelease is IUnknown::Release (slot 2).
func comRelease(itf uintptr) {
	if itf == 0 {
		return
	}
	syscall.SyscallN(vtableCall(itf, 2), itf)
}

// queryInterface wraps IUnknown::QueryInterface (slot 0).
func queryInterface(itf uintptr, iid *windows.GUID) (uintptr, bool) {
	var out uintptr
	r, _, _ := syscall.SyscallN(vtableCall(itf, 0), itf,
		uintptr(unsafe.Pointer(iid)), uintptr(unsafe.Pointer(&out)))
	return out, r == 0 && out != 0
}

// roGetActivationFactory loads a WinRT class's factory interface.
func roGetActivationFactory(class string, iid *windows.GUID) (uintptr, error) {
	hs, err := newHString(class)
	if err != nil {
		return 0, err
	}
	defer hs.free()
	var factory uintptr
	r, _, _ := procRoGetActivationFactory.Call(
		hs.h,
		uintptr(unsafe.Pointer(iid)),
		uintptr(unsafe.Pointer(&factory)),
	)
	if r != 0 || factory == 0 {
		return 0, syscall.Errno(r)
	}
	return factory, nil
}

// notifyDesktop shows a native Windows toast. key/icon/actions/onAction
// are unused in v1 (no click-through callback yet — the in-app banner
// remains the click surface; see the file comment). Returns an error on
// any WinRT failure so the caller keeps its banner path.
func notifyDesktop(title, body, key, icon string, actions []string, onAction func(string)) error {
	toastMu.Lock()
	defer toastMu.Unlock()

	// Manager → notifier (bound to the registered AUMID).
	manager, err := roGetActivationFactory("Windows.UI.Notifications.ToastNotificationManager", &iidIToastNotificationManagerStatics)
	if err != nil {
		return err
	}
	defer comRelease(manager)
	aumid, err := newHString(toastAUMID)
	if err != nil {
		return err
	}
	defer aumid.free()
	var notifier uintptr
	r, _, _ := syscall.SyscallN(vtableCall(manager, vtManagerCreateWithId), manager,
		aumid.h, uintptr(unsafe.Pointer(&notifier)))
	if r != 0 || notifier == 0 {
		return syscall.Errno(r)
	}
	defer comRelease(notifier)

	// XmlDocument: activate the instance, QI the document + IO, LoadXml.
	docClass, err := newHString("Windows.Data.Xml.Dom.XmlDocument")
	if err != nil {
		return err
	}
	defer docClass.free()
	var inspectable uintptr
	r, _, _ = procRoActivateInstance.Call(docClass.h, uintptr(unsafe.Pointer(&inspectable)))
	if r != 0 || inspectable == 0 {
		return syscall.Errno(r)
	}
	defer comRelease(inspectable)
	doc, ok := queryInterface(inspectable, &iidIXmlDocument)
	if !ok {
		return syscall.EINVAL
	}
	defer comRelease(doc)
	docIO, ok := queryInterface(inspectable, &iidIXmlDocumentIO)
	if !ok {
		return syscall.EINVAL
	}
	defer comRelease(docIO)
	xml, err := newHString(toastXML(title, body))
	if err != nil {
		return err
	}
	defer xml.free()
	r, _, _ = syscall.SyscallN(vtableCall(docIO, vtXmlIOLoadXml), docIO, xml.h)
	if r != 0 {
		return syscall.Errno(r)
	}

	// ToastNotification from the XML, then Show.
	factory, err := roGetActivationFactory("Windows.UI.Notifications.ToastNotification", &iidIToastNotificationFactory)
	if err != nil {
		return err
	}
	defer comRelease(factory)
	var toast uintptr
	r, _, _ = syscall.SyscallN(vtableCall(factory, vtFactoryCreate), factory,
		doc, uintptr(unsafe.Pointer(&toast)))
	if r != 0 || toast == 0 {
		return syscall.Errno(r)
	}
	defer comRelease(toast)
	r, _, _ = syscall.SyscallN(vtableCall(notifier, vtNotifierShow), notifier, toast)
	if r != 0 {
		return syscall.Errno(r)
	}
	return nil
}
