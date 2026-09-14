package gui

// comabi.go (slice 201) — the COM ABI constants for the Windows
// Start-Menu shortcut registration (own AUMID for toasts): shared on
// every platform so the tests pin the values in CI on all build
// targets, the same way toastxml.go pins the payload. The Windows-only
// caller is shortcut_windows.go; nothing here imports x/sys.

import "path/filepath"

// winGUID mirrors the Windows GUID / x/sys windows.GUID layout
// (Data1 uint32, Data2/Data3 uint16, Data4 [8]byte).
type winGUID struct {
	Data1 uint32
	Data2 uint16
	Data3 uint16
	Data4 [8]byte
}

// The shortcut-registration COM classes and interfaces — pinned against
// mingw-w64 headers (research notes in the WORKLOG session entry):
//   - CLSID_ShellLink   (shobjidl.h)  {00021401-...-46}
//   - IID_IShellLinkW   (shobjidl.h)  {000214F9-...-46}
//   - IID_IPersistFile  (objidl.h)    {0000010B-...-46}
//   - IID_IPropertyStore(propsys.h)   {886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99}
var (
	clsidShellLink = winGUID{
		Data1: 0x00021401, Data2: 0x0000, Data3: 0x0000,
		Data4: [8]byte{0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46},
	}
	iidIShellLinkW = winGUID{
		Data1: 0x000214F9, Data2: 0x0000, Data3: 0x0000,
		Data4: [8]byte{0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46},
	}
	iidIPersistFile = winGUID{
		Data1: 0x0000010B, Data2: 0x0000, Data3: 0x0000,
		Data4: [8]byte{0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46},
	}
	iidIPropertyStore = winGUID{
		Data1: 0x886D8EEB, Data2: 0x8CF2, Data3: 0x4446,
		Data4: [8]byte{0x8D, 0x02, 0xCD, 0xBA, 0x1D, 0xBD, 0xCF, 0x99},
	}
)

// propertyKey is Windows' PROPERTYKEY (fmtid + property id).
type propertyKey struct {
	fmtid winGUID
	pid   uint32
}

// pkeyAppUserModelID is PKEY_AppUserModel.ID (mingw-w64 propkey.h) — the
// property that turns a Start-Menu shortcut into a toast-registered
// AUMID. fmtid tail is E1-D4-2D-E1-D5-F3 (not the "E1D42DE4D436" typo
// some blog posts carry).
var pkeyAppUserModelID = propertyKey{
	fmtid: winGUID{
		Data1: 0x9F4C2855, Data2: 0x9F79, Data3: 0x4B39,
		Data4: [8]byte{0xA8, 0xD0, 0xE1, 0xD4, 0x2D, 0xE1, 0xD5, 0xF3},
	},
	pid: 5,
}

// propVariantVTLPWSTR is VARTYPE VT_LPWSTR (wtypes.h).
const propVariantVTLPWSTR = 31

// propVariant is the head of Windows' PROPVARIANT for VT_LPWSTR values:
// vt + three reserved WORDs (8 bytes), then the union — the string
// pointer sits at offset 8; the union is 16 bytes on x64, 24 total.
// Only the head is laid out: SetValue copies the string, and the tail is
// zero padding that a zero-initialized struct provides.
type propVariant struct {
	vt  uint16
	_   [6]byte
	ptr uintptr
	_   [8]byte
}

// ourAUMID: Uniclient's own AppUserModelID (top-level.product form).
// Toasts created with this AUMID carry the shortcut's name/icon as the
// source ("Uniclient", not "Windows PowerShell").
const ourAUMID = "DarkReaperBoy.Uniclient"

// shortcutPath: the per-user Start-Menu Programs .lnk from APPDATA —
// where the AUMID-carrying shortcut is persisted (pure, tested on every
// platform).
func shortcutPath(appData string) string {
	if appData == "" {
		return ""
	}
	return filepath.Join(appData, "Microsoft", "Windows", "Start Menu", "Programs", "Uniclient.lnk")
}
