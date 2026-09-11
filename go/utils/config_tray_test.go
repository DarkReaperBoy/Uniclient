package utils

import "testing"

// TestEffectiveSystemTray: nil = default ON (tdesktop parity), explicit
// values honored.
func TestEffectiveSystemTray(t *testing.T) {
	if !EffectiveSystemTray(AppConfig{}) {
		t.Fatal("nil pointer should default to tray on")
	}
	off := false
	if EffectiveSystemTray(AppConfig{SystemTray: &off}) {
		t.Fatal("explicit off should be off")
	}
	on := true
	if !EffectiveSystemTray(AppConfig{SystemTray: &on}) {
		t.Fatal("explicit on should be on")
	}
}
