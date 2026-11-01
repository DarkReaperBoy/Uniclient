package gui

import (
	"fmt"
	"path/filepath"
	"testing"
	"unsafe"
)

func canonical(g winGUID) string {
	return fmt.Sprintf("{%08X-%04X-%04X-%02X%02X-%02X%02X%02X%02X%02X%02X}",
		g.Data1, g.Data2, g.Data3,
		g.Data4[0], g.Data4[1], g.Data4[2], g.Data4[3],
		g.Data4[4], g.Data4[5], g.Data4[6], g.Data4[7])
}

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
		{"IID_IToastNotification2", iidIToastNotification2, "{9DFB9FD1-143A-490E-90BF-B9FBA7132DE7}"},
	}
	for _, c := range cases {
		if got := canonical(c.got); got != c.want {
			t.Errorf("%s = %s, want %s", c.name, got, c.want)
		}
	}
}

func TestComABIPkey(t *testing.T) {
	if got := canonical(pkeyAppUserModelID.fmtid); got != "{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}" {
		t.Errorf("PKEY_AppUserModel_ID fmtid = %s", got)
	}
	if pkeyAppUserModelID.pid != 5 {
		t.Errorf("PKEY_AppUserModel_ID pid = %d, want 5", pkeyAppUserModelID.pid)
	}
}

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

func TestOurAUMID(t *testing.T) {
	if ourAUMID != "DarkReaperBoy.Uniclient" {
		t.Errorf("ourAUMID = %q", ourAUMID)
	}
}
