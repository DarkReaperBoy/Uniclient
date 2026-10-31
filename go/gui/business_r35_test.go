package gui

import "testing"

// TestBizRecipientWidgetsAreSeededAndRead pins R35: the greeting/away
// editor's recipient checkboxes (New chats / Existing chats / Contacts /
// Non-contacts), the exclude toggle and the away editor's offline toggle
// were pure decoration — never seeded from the wire flags, and never read
// back on Save. bizEditorData sent the wire-primed st.recips/st.offline,
// so nothing the user checked ever applied and the checkboxes didn't even
// reflect the server's current state. They are now seeded on editor open
// (seedBizRecipWidgets, from bizToggleEditor) and read back in
// bizEditorData on the UI goroutine, with a client-side at-least-one
// guard (the server rejects an all-false selection).
func TestBizRecipientWidgetsAreSeededAndRead(t *testing.T) {
	a := &App{}
	a.businessPage = &businessPageState{
		accountID: "acc",
		loaded:    true,
		info: map[string]interface{}{
			"greeting": map[string]interface{}{
				"message":          "hello there",
				"shortcut_id":      float64(7),
				"no_activity_days": float64(21),
				"existing_chats":   true,
				"new_chats":        true,
				"contacts":         false,
				"non_contacts":     false,
				"exclude_selected": true,
				"offline_only":     true, // away-only flag, must not leak into greeting
			},
		},
	}
	st := a.businessPage

	// Seeding: bizToggleEditor primes the state (wire → recips/offline),
	// then seedBizRecipWidgets primes the widgets from that state.
	// (The toggle installs a COPY — R34 — so the tests read the new head.)
	a.bizToggleEditor("greeting")
	st = a.businessPage
	if st == nil || st.editor != "greeting" {
		t.Fatal("greeting editor must be open after toggle")
	}
	growBools(&bizRecChks, 4)
	if !bizRecChks[0].Value { // New chats ← new_chats=true
		t.Fatal("New chats checkbox must be seeded true from new_chats")
	}
	if !bizRecChks[1].Value { // Existing chats ← existing_chats=true
		t.Fatal("Existing chats checkbox must be seeded true from existing_chats")
	}
	if bizRecChks[2].Value || bizRecChks[3].Value {
		t.Fatal("Contacts/Non-contacts must be seeded false")
	}
	if !bizExcludeChk.Value {
		t.Fatal("exclude checkbox must be seeded from exclude_selected")
	}

	// Read-back: the user flips Contacts on and Existing chats off; Save
	// must carry the WIDGET state, not the stale wire-primed struct.
	bizRecChks[1].Value = false
	bizRecChks[2].Value = true
	data, err := a.bizEditorData(st)
	if err != nil {
		t.Fatalf("bizEditorData must accept a valid selection: %v", err)
	}
	if data["existing_chats"] != false {
		t.Fatalf("existing_chats must follow the checkbox (false), got %v", data["existing_chats"])
	}
	if data["new_chats"] != true {
		t.Fatalf("new_chats must stay checked, got %v", data["new_chats"])
	}
	if data["contacts"] != true {
		t.Fatalf("contacts must follow the checkbox (true), got %v", data["contacts"])
	}
	if data["non_contacts"] != false {
		t.Fatalf("non_contacts must stay unchecked, got %v", data["non_contacts"])
	}
	if data["exclude_selected"] != true {
		t.Fatalf("exclude_selected must follow the checkbox, got %v", data["exclude_selected"])
	}
	if data["message"] != "hello there" {
		t.Fatalf("message must come from the editor, got %q", data["message"])
	}
	if data["no_activity_days"] != 21 {
		t.Fatalf("no_activity_days must ride the state (21), got %v", data["no_activity_days"])
	}

	// The at-least-one guard: all four classes unchecked → client-side
	// error, no map produced.
	bizRecChks[0].Value = false
	bizRecChks[1].Value = false
	bizRecChks[2].Value = false
	bizRecChks[3].Value = false
	if _, err := a.bizEditorData(st); err == nil {
		t.Fatal("an all-false selection must fail the at-least-one guard")
	}
}

// TestBizAwayOfflineWidgetIsReadBack pins R35's away half: offline_only
// used to be sent as the wire-primed st.offline no matter what the user
// toggled; it now follows the checkbox. Also checks the custom-schedule
// date validation still guards the same path.
func TestBizAwayOfflineWidgetIsReadBack(t *testing.T) {
	a := &App{}
	a.businessPage = &businessPageState{
		accountID: "acc",
		loaded:    true,
		info: map[string]interface{}{
			"away": map[string]interface{}{
				"message":      "gone fishing",
				"offline_only": false,
				"schedule":     "always",
			},
		},
	}
	st := a.businessPage

	a.bizToggleEditor("away")
	st = a.businessPage
	if st == nil || st.editor != "away" {
		t.Fatal("away editor must be open after toggle")
	}
	if bizOfflineChk.Value {
		t.Fatal("offline checkbox must be seeded false from offline_only=false")
	}

	bizOfflineChk.Value = true
	bizRecChks[0].Value = true // at least one recipient, or the guard fires first
	bizMsgEd.SetText("gone fishing")
	data, err := a.bizEditorData(st)
	if err != nil {
		t.Fatalf("away editor data: %v", err)
	}
	if data["offline_only"] != true {
		t.Fatalf("offline_only must follow the checkbox (true), got %v", data["offline_only"])
	}
	if data["schedule"] != "always" {
		t.Fatalf("schedule must ride the state, got %v", data["schedule"])
	}

	// Custom schedule without valid dates keeps the existing guard.
	a.updateBusinessPage(func(n *businessPageState) bool {
		n.awayMode = "custom"
		return true
	})
	bizFromEd.SetText("not-a-date")
	bizToEd.SetText("2026-12-31")
	if _, err := a.bizEditorData(a.businessPage); err == nil {
		t.Fatal("custom schedule with a bad date must fail validation")
	}
}
