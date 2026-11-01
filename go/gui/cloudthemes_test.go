package gui

import (
	"testing"

	"uniclient/cores"
)

func TestArgbToHex(t *testing.T) {
	cases := map[int]string{
		0xFF4F6EF7: "#4F6EF7",
		0x40A358:   "#40A358",
		0xE0851E:   "#E0851E",
		0:          "",
	}
	for argb, want := range cases {
		if got := argbToHex(argb); got != want {
			t.Errorf("argbToHex(%d) = %q, want %q", argb, got, want)
		}
	}
}

func TestCloudThemeDlgStateFields(t *testing.T) {
	th := cores.CloudThemeInfo{ID: 12, Title: "Peach", Slug: "peach", AccentColor: 0xFFE0851E}
	st := &cloudThemeDlgState{accountID: "a1", theme: th}
	if st.accountID != "a1" || st.theme.ID != 12 || st.theme.Slug != "peach" {
		t.Fatalf("state = %+v", st)
	}
}

func TestCloudThemeAccentConversion(t *testing.T) {
	th := cores.CloudThemeInfo{AccentColor: 0xFF40A358}
	hex := argbToHex(th.AccentColor)
	c, ok := parseAccentHex(hex)
	if !ok {
		t.Fatalf("parseAccentHex(%q) failed", hex)
	}
	if c.R != 0x40 || c.G != 0xA3 || c.B != 0x58 {
		t.Errorf("accent = %+v", c)
	}
	if argbToHex(0) != "" {
		t.Error("unset accent must convert to empty hex")
	}
}
