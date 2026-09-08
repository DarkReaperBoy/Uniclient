package gui

import (
	"testing"
)

// Drawer customization (AyuGram parity slice 38).

func TestDrawerRowHidden(t *testing.T) {
	hidden := []string{drawerItemSaved, drawerItemCalls}
	if !drawerRowHidden(hidden, drawerItemSaved) {
		t.Error("saved should be hidden")
	}
	if !drawerRowHidden(hidden, drawerItemCalls) {
		t.Error("calls should be hidden")
	}
	if drawerRowHidden(hidden, drawerItemContacts) {
		t.Error("contacts should be visible")
	}
	if drawerRowHidden(nil, drawerItemGhost) {
		t.Error("nil hidden list hides nothing")
	}
}

func TestDrawerCustomItems(t *testing.T) {
	items := drawerCustomItems()
	if len(items) != 6 {
		t.Fatalf("customizable items = %d, want 6", len(items))
	}
	ids := map[string]bool{}
	for _, it := range items {
		if it.id == "" || it.label == "" {
			t.Errorf("item %+v has empty id/label", it)
		}
		ids[it.id] = true
	}
	for _, want := range []string{drawerItemSaved, drawerItemContacts, drawerItemCalls, drawerItemGhost, drawerItemNewGroup, drawerItemNewChan} {
		if !ids[want] {
			t.Errorf("missing drawer item %q", want)
		}
	}
}
