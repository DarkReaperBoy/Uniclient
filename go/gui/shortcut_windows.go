//go:build windows

package gui

// shortcut_windows.go — slice 201: the app's own AUMID for Windows
// toasts. Registers the per-user Start-Menu shortcut carrying
// PKEY_AppUserModel.ID = "DarkReaperBoy.Uniclient" so toasts raised by
// the slice-200 transport show "Uniclient" as their source (instead of
// riding PowerShell's pre-registered AUMID and showing "Windows
// PowerShell").
//
// Pure-Go COM, the taskbar_windows.go pattern: CoCreateInstance(CLSID_
// ShellLink, IID_IShellLinkW) → SetPath/SetWorkingDirectory/
// SetIconLocation → QI IPropertyStore → SetValue(PKEY_AppUserModel.ID)
// → Commit → QI IPersistFile → Save. The property store commits BEFORE
// IPersistFile::Save so the AUMID rides the persisted .lnk (the recipe
// from the AppUserModelID docs). ABI (IIDs, vtable slots, PROPERTYKEY)
// pinned against mingw-w64 shobjidl.h/objidl.h/propsys.h/propkey.h —
// constants live in the shared comabi.go so CI pins them on every
// build target.
//
// Failure semantics stay slice-200: resolvedToastAUMID falls back to
// PowerShell's AUMID, toasts still render, never a crash (§1.10).

import (
	"errors"
	"os"
	"path/filepath"
	"sync"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

// vtable slots — IUnknown 0-2, then declaration order (mingw-w64):
const (
	vtShellLinkSetWorkingDirectory = 9  // IShellLinkW::SetWorkingDirectory
	vtShellLinkSetIconLocation     = 17 // IShellLinkW::SetIconLocation
	vtShellLinkSetPath             = 20 // IShellLinkW::SetPath
	vtPersistFileSave              = 6  // IPersistFile::Save
	vtPropertyStoreSetValue        = 6  // IPropertyStore::SetValue
	vtPropertyStoreCommit          = 7  // IPropertyStore::Commit
)

const clsctxInprocServer = 0x1

var (
	aumidOnce     sync.Once
	aumidResolved string
)

// guidRef reinterprets a shared-ABI winGUID as the x/sys windows.GUID —
// identical layouts (uint32 + 2×uint16 + [8]byte), pinned by the
// comabi tests.
func guidRef(g *winGUID) *windows.GUID {
	return (*windows.GUID)(unsafe.Pointer(g))
}

// ensureAUMIDShortcut (re)creates the Start-Menu shortcut with our
// AUMID. Idempotent and cheap; called once per process from
// resolvedToastAUMID.
func ensureAUMIDShortcut() error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	lnk := shortcutPath(os.Getenv("APPDATA"))
	if lnk == "" {
		return errors.New("shortcut: no APPDATA")
	}

	// CoInitializeEx is idempotent per-thread; S_FALSE is fine.
	procCoInitializeEx.Call(0, 2 /*COINIT_APARTMENTTHREADED*/)

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
	// The shortcut icon: the exe itself, index 0.
	if r, _, _ = syscall.SyscallN(vtableCall(sl, vtShellLinkSetIconLocation), sl,
		uintptr(unsafe.Pointer(&exe16[0])), 0); r != 0 {
		return syscall.Errno(r)
	}

	// System.AppUserModel.ID → Commit (before the persist).
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

	// Persist the .lnk.
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
		uintptr(unsafe.Pointer(&lnk16[0])), 1 /*fRemember*/); r != 0 {
		return syscall.Errno(r)
	}
	return nil
}

// resolvedToastAUMID: our own AUMID once the shortcut registration has
// succeeded (one attempt per process), PowerShell's pre-registered AUMID
// as the always-works fallback — the slice-200 v1 semantics, never a
// crash, toasts keep rendering either way.
func resolvedToastAUMID() string {
	aumidOnce.Do(func() {
		aumidResolved = powerShellAUMID
		if err := ensureAUMIDShortcut(); err == nil {
			aumidResolved = ourAUMID
		}
	})
	return aumidResolved
}
