package gui

import (
	"image/color"
	"testing"

	"uniclient/engine"
	"uniclient/utils"
)

// Anti-recall completion (slice 80, AyuGram §52): config-bridge toggles,
// per-chat clearing, and the Ayu fade styling on recalled bubbles.

func TestConfigFieldChangesAntiRecall(t *testing.T) {
	for _, field := range []string{"ayu_save_deleted", "ayu_save_history", "ayu_save_for_bots"} {
		c := configFieldChanges(field, false)
		if c == nil {
			t.Fatalf("configFieldChanges(%q) = nil", field)
		}
		var got *bool
		switch field {
		case "ayu_save_deleted":
			got = c.AyuSaveDeleted
		case "ayu_save_history":
			got = c.AyuSaveHistory
		case "ayu_save_for_bots":
			got = c.AyuSaveForBots
		}
		if got == nil || *got {
			t.Errorf("%q → %+v, want pointer to false", field, got)
		}
	}
	if c := configFieldChanges("ayu_bogus", true); c != nil {
		t.Error("unknown field must return nil")
	}
}

func TestAntiRecallFromConfig(t *testing.T) {
	// Nil keys → engine defaults (true/true/false).
	c := utils.DefaultConfig()
	d, h, b := antiRecallFromConfig(&c)
	if !d || !h || b {
		t.Fatalf("defaults = %v/%v/%v, want true/true/false", d, h, b)
	}
	// Set keys win.
	f, tr := false, true
	c.AyuSaveDeleted, c.AyuSaveHistory, c.AyuSaveForBots = &f, &f, &tr
	d, h, b = antiRecallFromConfig(&c)
	if d || h || !b {
		t.Fatalf("explicit = %v/%v/%v, want false/false/true", d, h, b)
	}
}

func TestDeletedBubbleFade(t *testing.T) {
	// The fade helper: recalled bubbles halve the alpha.
	bg := color.NRGBA{R: 0x20, G: 0x21, B: 0x22, A: 0xFF}
	got := deletedFade(bg, true)
	if got.A != 0x80 {
		t.Errorf("faded alpha = %d, want 0x80", got.A)
	}
	if got.R != bg.R || got.G != bg.G || got.B != bg.B {
		t.Errorf("fade changed RGB: %v → %v", bg, got)
	}
	// Non-deleted: untouched.
	if got := deletedFade(bg, false); got != bg {
		t.Errorf("non-deleted = %v, want %v", got, bg)
	}
}

func TestHeaderMenuClearDeleted(t *testing.T) {
	for _, c := range []engine.ChatInfo{
		{AccountID: "a", ChatID: "u1", Type: engine.ChatTypeDMVal},
		{AccountID: "a", ChatID: "g1", Type: engine.ChatTypeGroupVal},
		{AccountID: "a", ChatID: "c1", Type: engine.ChatTypeChanVal},
	} {
		items := headerMenuItems(c, false, false)
		if !containsAction(items, "cleardeleted") {
			t.Errorf("type %d menu missing Clear deleted messages", c.Type)
		}
	}
}
