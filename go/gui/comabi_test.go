package gui

import (
        "fmt"
        "path/filepath"
        "testing"
        "unsafe"
)

// canonical renders a winGUID in the canonical Windows registry form —
// the form every IID/CLSID is quoted in, so the pinned values can be
// checked against the primary sources by eye.
func canonical(g winGUID) string {
        return fmt.Sprintf("{%08X-%04X-%04X-%02X%02X-%02X%02X%02X%02X%02X%02X}",
                g.Data1, g.Data2, g.Data3,
                g.Data4[0], g.Data4[1], g.Data4[2], g.Data4[3],
                g.Data4[4], g.Data4[5], g.Data4[6], g.Data4[7])
}

// TestComABIGUIDs (slice 201): the COM class/interface IDs for the
// Start-Menu shortcut registration, pinned against mingw-w64 headers
// (shobjidl.h: IID_IShellLinkW + CLSID_ShellLink; objidl.h:
// IID_IPersistFile; propsys.h: IID_IPropertyStore). A drift here is a
// silent QueryInterface failure on Windows, so it is locked in CI on
// every build target.
func TestComABIGUIDs(t *testing.T) {
        cases := []struct {
                name string
                got  winGUID
                want string
        }{
                {"CLSID_ShellLink", clsidShellLink, "{00021401-0000-0000-C000-000000000046}"},
                {"IID_IShellLinkW", iidIShellLinkW, "{000214F9-0000-0000-C000-000000000046}"},
                {"IID_IPersistFile", iidIPersistFile, "{0000010B-0000-0000-C000-000000000046}"},
                {"IID_IPropertyStore", iidIPropertyStore, "{886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99}"},
        }
        for _, c := range cases {
                if got := canonical(c.got); got != c.want {
                        t.Errorf("%s = %s, want %s", c.name, got, c.want)
                }
        }
}

// TestComABIPkey (slice 201): PKEY_AppUserModel_ID — mingw-w64 propkey.h
// (fmtid {9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}, pid 5). Note the fmtid's
// tail bytes: E1-D4-2D-E1-D5-F3 — blog-copied variants ending in
// "E1D42DE4D436" are wrong.
func TestComABIPkey(t *testing.T) {
        if got := canonical(pkeyAppUserModelID.fmtid); got != "{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}" {
                t.Errorf("PKEY_AppUserModel_ID fmtid = %s", got)
        }
        if pkeyAppUserModelID.pid != 5 {
                t.Errorf("PKEY_AppUserModel_ID pid = %d, want 5", pkeyAppUserModelID.pid)
        }
}

// TestComABIPropVariant (slice 201): the VT_LPWSTR PROPVARIANT layout —
// 2-byte vt + 6 bytes reserved, union at offset 8 (the LPWSTR pointer),
// 24 bytes total on 64-bit (union padded to 16). Pinned so a struct edit
// on another platform cannot silently shift the pointer the Windows COM
// call reads.
func TestComABIPropVariant(t *testing.T) {
        if unsafe.Offsetof(propVariant{}.ptr) != 8 {
                t.Errorf("propVariant.ptr offset = %d, want 8", unsafe.Offsetof(propVariant{}.ptr))
        }
        if unsafe.Offsetof(propVariant{}.vt) != 0 {
                t.Errorf("propVariant.vt offset = %d, want 0", unsafe.Offsetof(propVariant{}.vt))
        }
        if sz := unsafe.Sizeof(propVariant{}); sz < 24 {
                t.Errorf("propVariant size = %d, want >= 24 (x64 union pad)", sz)
        }
        if propVariantVTLPWSTR != 31 {
                t.Errorf("VT_LPWSTR = %d, want 31", propVariantVTLPWSTR)
        }
}

// TestShortcutPath (slice 201): the shortcut lands in the per-user Start
// Menu Programs folder and is named after the app (slash-normalized so
// the pin holds on every CI build target).
func TestShortcutPath(t *testing.T) {
        got := filepath.ToSlash(shortcutPath("C:/Users/o/AppData/Roaming"))
        want := "C:/Users/o/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Uniclient.lnk"
        if got != want {
                t.Errorf("shortcutPath = %q, want %q", got, want)
        }
        if shortcutPath("") != "" {
                t.Errorf("empty APPDATA must yield no shortcut path")
        }
}

// TestOurAUMID (slice 201): the AUMID is stable (toplevel.product — the
// Windows convention) and matches what the toast transport resolves to.
func TestOurAUMID(t *testing.T) {
        if ourAUMID != "DarkReaperBoy.Uniclient" {
                t.Errorf("ourAUMID = %q", ourAUMID)
        }
}
