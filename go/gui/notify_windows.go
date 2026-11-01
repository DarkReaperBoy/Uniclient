//go:build windows

package gui

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

const (
	vtManagerCreateWithId = 7
	vtFactoryCreate       = 6
	vtNotifierShow        = 6
	vtXmlIOLoadXml        = 6
	vtToast2PutTag        = 6
	vtToast2PutGroup      = 8
)

const toastGroup = "uniclient"

const powerShellAUMID = `1AC14E77-02E7-4E5D-B744-2EB1AE5198B7\WindowsPowerShell\v1.0`

var toastMu sync.Mutex

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

func vtableCall(itf uintptr, idx int) uintptr {
	lpVtbl := *(*uintptr)(unsafe.Pointer(itf))
	return *(*uintptr)(unsafe.Pointer(lpVtbl + uintptr(idx)*unsafe.Sizeof(uintptr(0))))
}

func comRelease(itf uintptr) {
	if itf == 0 {
		return
	}
	syscall.SyscallN(vtableCall(itf, 2), itf)
}

func queryInterface(itf uintptr, iid *windows.GUID) (uintptr, bool) {
	var out uintptr
	r, _, _ := syscall.SyscallN(vtableCall(itf, 0), itf,
		uintptr(unsafe.Pointer(iid)), uintptr(unsafe.Pointer(&out)))
	return out, r == 0 && out != 0
}

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

func notifyDesktop(title, body, key, icon string, actions []string, onAction func(string)) error {
	toastMu.Lock()
	defer toastMu.Unlock()

	manager, err := roGetActivationFactory("Windows.UI.Notifications.ToastNotificationManager", &iidIToastNotificationManagerStatics)
	if err != nil {
		return err
	}
	defer comRelease(manager)
	aumid, err := newHString(resolvedToastAUMID())
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
	launch := ""
	if acc, chat, ok := splitNotifyKey(key); ok {
		launch = buildOpenURI(acc, chat)
	}
	xml, err := newHString(toastXML(title, body, launch, toastImageSrc(icon)))
	if err != nil {
		return err
	}
	defer xml.free()
	r, _, _ = syscall.SyscallN(vtableCall(docIO, vtXmlIOLoadXml), docIO, xml.h)
	if r != 0 {
		return syscall.Errno(r)
	}

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
	if tag := toastTag(key); tag != "" {
		if t2, ok := queryInterface(toast, guidRef(&iidIToastNotification2)); ok {
			defer comRelease(t2)
			if hs, err := newHString(tag); err == nil {
				r, _, _ = syscall.SyscallN(vtableCall(t2, vtToast2PutTag), t2, hs.h)
				hs.free()
				if r == 0 {
					if gs, err := newHString(toastGroup); err == nil {
						syscall.SyscallN(vtableCall(t2, vtToast2PutGroup), t2, gs.h)
						gs.free()
					}
				}
			}
		}
	}
	r, _, _ = syscall.SyscallN(vtableCall(notifier, vtNotifierShow), notifier, toast)
	if r != 0 {
		return syscall.Errno(r)
	}
	return nil
}
