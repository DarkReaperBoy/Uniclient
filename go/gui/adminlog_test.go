package gui

import (
	"testing"

	"uniclient/cores"
	"uniclient/engine"
)

// Admin log / Recent Actions panel (slice 177, parity row "Moderation
// (admin log, restrictions)" — tdesktop's Recent Actions window): pure
// logic — header-menu gating, paging cursor, filter chips, event row
// composition, ActionData media extraction. Layout is verified by
// compile + review.

func TestHeaderMenuAdminLogEntry(t *testing.T) {
	// Admins of groups/channels see "Recent actions".
	c := engine.ChatInfo{Type: engine.ChatTypeChanVal, Title: "News", IsAdmin: true}
	found := false
	for _, it := range headerMenuItems(c, false, false, false) {
		if it.id == "adminlog" {
			found = true
		}
	}
	if !found {
		t.Fatal("admin channel menu lacks Recent actions")
	}
	c2 := engine.ChatInfo{Type: engine.ChatTypeGroupVal, Title: "Group", IsAdmin: true}
	found2 := false
	for _, it := range headerMenuItems(c2, false, false, false) {
		if it.id == "adminlog" {
			found2 = true
		}
	}
	if !found2 {
		t.Fatal("admin supergroup menu lacks Recent actions")
	}

	// Non-admins never see it (tdesktop semantics).
	c3 := engine.ChatInfo{Type: engine.ChatTypeChanVal, Title: "News", IsAdmin: false}
	for _, it := range headerMenuItems(c3, false, false, false) {
		if it.id == "adminlog" {
			t.Fatal("non-admin sees Recent actions")
		}
	}
	// DMs never see it.
	c4 := engine.ChatInfo{Type: engine.ChatTypeDMVal, IsAdmin: true}
	for _, it := range headerMenuItems(c4, false, false, false) {
		if it.id == "adminlog" {
			t.Fatal("DM menu has Recent actions")
		}
	}
}

func TestAdminLogMaxID(t *testing.T) {
	if got := adminLogMaxID(nil); got != 0 {
		t.Fatalf("empty events maxID = %d", got)
	}
	evs := []cores.AdminLogEvent{
		{ID: 500}, {ID: 120}, {ID: 900},
	}
	if got := adminLogMaxID(evs); got != 120 {
		t.Fatalf("maxID = %d, want 120", got)
	}
}

func TestAdminFilterChips(t *testing.T) {
	if len(adminFilterDefs) < 10 {
		t.Fatalf("filter chip set too small: %d", len(adminFilterDefs))
	}
	seen := map[string]bool{}
	for _, d := range adminFilterDefs {
		if d.id == "" || d.label == "" {
			t.Fatalf("bad chip def %+v", d)
		}
		seen[d.id] = true
	}
	for _, want := range []string{"join", "ban", "promote", "pinned", "messages", "group_call", "edit", "delete"} {
		if !seen[want] {
			t.Fatalf("missing filter %q", want)
		}
	}
	// Toggling a filter flips it in the active set (pure).
	active := map[string]bool{}
	adminToggleFilter(active, "ban")
	if !active["ban"] {
		t.Fatal("toggle did not activate ban")
	}
	adminToggleFilter(active, "ban")
	if active["ban"] {
		t.Fatal("second toggle did not deactivate ban")
	}
}

func TestAdminEventRow(t *testing.T) {
	e := cores.AdminLogEvent{
		ID:       1,
		Date:     1726000000,
		UserID:   42,
		UserName: "Jane",
		Action:   "pinned a message",
		Detail:   "in General",
	}
	if got := adminEventHeadline(e); got != "Jane" {
		t.Fatalf("headline = %q", got)
	}
	if got := adminEventActionText(e); got != "pinned a message" {
		t.Fatalf("action = %q", got)
	}
	if got := adminEventSub(e); got != "in General" {
		t.Fatalf("sub = %q", got)
	}

	// Old → new change rows.
	e2 := cores.AdminLogEvent{
		UserName: "Bob",
		Action:   "changed the group name",
		OldValue: "Before",
		NewValue: "After",
	}
	chgs := adminEventChanges(e2)
	if len(chgs) != 2 || chgs[0] != "Before" || chgs[1] != "After" {
		t.Fatalf("changes = %v", chgs)
	}
	// No changes → nil.
	e3 := cores.AdminLogEvent{UserName: "Bob", Action: "joined"}
	if chs := adminEventChanges(e3); chs != nil {
		t.Fatalf("changes on change-less event = %v", chs)
	}
}

func TestAdminEventMedia(t *testing.T) {
	// Message events carry the media type + stripped thumb in ActionData.
	e := cores.AdminLogEvent{
		UserName: "Jane",
		Action:   "pinned a message",
		MsgText:  "hello",
		ActionData: map[string]interface{}{
			"media_type": float64(2),
			"thumb_b64":  "aGk=",
		},
	}
	mt, thumb := adminEventMedia(e)
	if mt != 2 || thumb != "aGk=" {
		t.Fatalf("media = %d %q", mt, thumb)
	}
	if !adminEventHasMessage(e) {
		t.Fatal("event with MsgText must be a message event")
	}
	// Plain event → no media.
	e2 := cores.AdminLogEvent{UserName: "Bob", Action: "joined"}
	mt2, thumb2 := adminEventMedia(e2)
	if mt2 != 0 || thumb2 != "" {
		t.Fatalf("plain event media = %d %q", mt2, thumb2)
	}
	if adminEventHasMessage(e2) {
		t.Fatal("event without MsgText is not a message event")
	}
}
