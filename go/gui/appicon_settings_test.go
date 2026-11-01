package gui

import "testing"

func TestAppIconPickerGrid(t *testing.T) {
	n := len(appIconSets())
	if got := appIconGridRows(n); got != (n+3)/4 {
		t.Fatalf("gridRows(%d) = %d, want %d", n, appIconGridRows(n), (n+3)/4)
	}
	if got := appIconGridRows(4); got != 1 {
		t.Fatalf("gridRows(4) = %d, want 1", got)
	}
	if got := appIconGridRows(5); got != 2 {
		t.Fatalf("gridRows(5) = %d, want 2", got)
	}
	for _, w := range []int{320, 480, 720} {
		cell := appIconCellWidth(w)
		if cell != w/4 {
			t.Fatalf("cellWidth(%d) = %d, want %d", w, cell, w/4)
		}
	}
}

func TestAppIconPickerSelection(t *testing.T) {
	sets := appIconSets()
	if !appIconIsSelected(sets[0], cfgSnapshot{AyuAppIcon: ""}) {
		t.Fatal("empty config selects the default set")
	}
	if !appIconIsSelected(sets[0], cfgSnapshot{AyuAppIcon: "default"}) {
		t.Fatal("explicit default selects the default set")
	}
	if !appIconIsSelected(sets[2], cfgSnapshot{AyuAppIcon: sets[2].ID}) {
		t.Fatal("matching ID selects its set")
	}
	for _, s := range sets {
		if appIconIsSelected(s, cfgSnapshot{AyuAppIcon: "bogus-id"}) {
			if s.ID != "default" {
				t.Fatalf("bogus config selects %q", s.ID)
			}
		}
	}
}

func TestAppIconPickerGate(t *testing.T) {
	if !appIconPickerSupported {
		t.Skip("platform without runtime icon application")
	}
}
