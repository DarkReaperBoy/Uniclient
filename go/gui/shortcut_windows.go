//go:build windows

package gui

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

const (
	vtShellLinkSetWorkingDirectory = 9
	vtShellLinkSetIconLocation     = 17
	vtShellLinkSetPath             = 20
	vtPersistFileSave              = 6
	vtPropertyStoreSetValue        = 6
	vtPropertyStoreCommit          = 7
)

const clsctxInprocServer = 0x1

var (
	aumidOnce     sync.Once
	aumidResolved string
)

func guidRef(g *winGUID) *windows.GUID {
	return (*windows.GUID)(unsafe.Pointer(g))
}

func ensureAUMIDShortcut() error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	lnk := shortcutPath(os.Getenv("APPDATA"))
	if lnk == "" {
		return errors.New("shortcut: no APPDATA")
	}

	procCoInitializeEx.Call(0, 2)

	var sl uintptr
	r, _, _ := procCoCreateInstance.Call(
		uintptr(unsafe.Pointer(&clsidShellLink)), 0, clsctxInprocServer,
		uintptr(unsafe.Pointer(guidRef(&iidIShellLinkW))),
		uintptr(unsafe.Pointer(&sl)))
	if r != 0 || sl == 0 {
		return syscall.Errno(r)
	}
	defer comRelease(sl)

	exe16, err := windows.UTF16FromString(exe)
	if err != nil {
		return err
	}
	if r, _, _ = syscall.SyscallN(vtableCall(sl, vtShellLinkSetPath), sl,
		uintptr(unsafe.Pointer(&exe16[0]))); r != 0 {
		return syscall.Errno(r)
	}
	dir16, err := windows.UTF16FromString(filepath.Dir(exe))
	if err != nil {
		return err
	}
	if r, _, _ = syscall.SyscallN(vtableCall(sl, vtShellLinkSetWorkingDirectory), sl,
		uintptr(unsafe.Pointer(&dir16[0]))); r != 0 {
		return syscall.Errno(r)
	}
	if r, _, _ = syscall.SyscallN(vtableCall(sl, vtShellLinkSetIconLocation), sl,
		uintptr(unsafe.Pointer(&exe16[0])), 0); r != 0 {
		return syscall.Errno(r)
	}

	ps, ok := queryInterface(sl, guidRef(&iidIPropertyStore))
	if !ok {
		return syscall.EINVAL
	}
	defer comRelease(ps)
	aumid16, err := windows.UTF16FromString(ourAUMID)
	if err != nil {
		return err
	}
	pv := propVariant{vt: propVariantVTLPWSTR, ptr: uintptr(unsafe.Pointer(&aumid16[0]))}
	if r, _, _ = syscall.SyscallN(vtableCall(ps, vtPropertyStoreSetValue), ps,
		uintptr(unsafe.Pointer(&pkeyAppUserModelID)),
		uintptr(unsafe.Pointer(&pv))); r != 0 {
		return syscall.Errno(r)
	}
	if r, _, _ = syscall.SyscallN(vtableCall(ps, vtPropertyStoreCommit), ps); r != 0 {
		return syscall.Errno(r)
	}

	pf, ok := queryInterface(sl, guidRef(&iidIPersistFile))
	if !ok {
		return syscall.EINVAL
	}
	defer comRelease(pf)
	lnk16, err := windows.UTF16FromString(lnk)
	if err != nil {
		return err
	}
	if r, _, _ = syscall.SyscallN(vtableCall(pf, vtPersistFileSave), pf,
		uintptr(unsafe.Pointer(&lnk16[0])), 1); r != 0 {
		return syscall.Errno(r)
	}
	return nil
}

func registerAUMIDMetadata(exe string) error {
	k, _, err := registry.CreateKey(registry.CURRENT_USER,
		`Software\Classes\AppUserModelId\`+ourAUMID, registry.SET_VALUE)
	if err != nil {
		return err
	}
	defer k.Close()
	if err := k.SetStringValue("DisplayName", "Uniclient"); err != nil {
		return err
	}
	icon := strings.ReplaceAll(exe, "\\", "/")
	return k.SetStringValue("IconUri", "file:///"+icon)
}

func resolvedToastAUMID() string {
	aumidOnce.Do(func() {
		aumidResolved = powerShellAUMID
		if err := ensureAUMIDShortcut(); err == nil {
			aumidResolved = ourAUMID
			if exe, err := os.Executable(); err == nil {
				_ = registerAUMIDMetadata(exe)
			}
		}
	})
	return aumidResolved
}
