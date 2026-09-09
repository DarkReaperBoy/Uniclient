package gui

import (
	"strings"
	"testing"

	"uniclient/engine"
)

// Share contact (slice 83): the DM profile panel's Share button copies a
// minimal vCard.

func TestVcardFor(t *testing.T) {
	u := engine.CachedUser{
		DisplayName: "Alice Smith",
		Phone:       "+123456789",
		Username:    "asmith",
	}
	v := vcardFor(u)
	for _, want := range []string{
		"BEGIN:VCARD", "VERSION:3.0", "FN:Alice Smith",
		"TEL;TYPE=CELL:+123456789", "NICKNAME:asmith", "END:VCARD",
	} {
		if !strings.Contains(v, want) {
			t.Errorf("vcard missing %q:\n%s", want, v)
		}
	}

	// Sparse profile: only the populated fields appear.
	v = vcardFor(engine.CachedUser{DisplayName: "Bob"})
	if strings.Contains(v, "TEL") || strings.Contains(v, "NICKNAME") {
		t.Errorf("sparse vcard leaked empty fields:\n%s", v)
	}
	if !strings.Contains(v, "FN:Bob") {
		t.Errorf("sparse vcard missing FN:\n%s", v)
	}
}
