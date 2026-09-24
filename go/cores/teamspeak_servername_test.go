package cores

import "testing"

// tests-first for BUGS.md B-16 — the virtual server's name must be
// stored from initserver and surfaced as the server dialog's title.
//
// The initserver handler's store branch was an empty `if` with a
// "Store server name etc" comment (staticcheck SA9003), and
// `virtualserver_name` was read NOWHERE else in the repo — while
// GetDialogs hardcoded Title: "Server Chat". So a TeamSpeak server's
// own name never reached the UI, and a live rename was invisible.
//
// This test uses only PRE-EXISTING API (tsHandleServerCommand +
// GetDialogs), so it is behaviorally RED before the fix: the title
// comes back as the hardcoded label.

func TestTeamSpeakInitserverStoresAndSurfacesServerName(t *testing.T) {
	tc := &TeamSpeakCore{}
	tc.tsHandleServerCommand(tsIncomingCmd{
		name: "initserver",
		params: map[string]string{
			"virtualserver_name":            "Arctic Test Server",
			"virtualserver_welcome_message": "welcome",
		},
	})

	tc.authed = true
	dialogs, err := tc.GetDialogs(PaginationOpts{})
	if err != nil {
		t.Fatal(err)
	}
	if len(dialogs) == 0 || dialogs[0].ID != "server" {
		t.Fatalf("dialogs = %+v, want the server entry first", dialogs)
	}
	if dialogs[0].Title != "Arctic Test Server" {
		t.Errorf("server dialog title = %q, want the virtualserver_name from initserver — a TS server's own name never reaches the UI (B-16)", dialogs[0].Title)
	}

	// A later initserver push (rename) overwrites.
	tc.tsHandleServerCommand(tsIncomingCmd{
		name:   "initserver",
		params: map[string]string{"virtualserver_name": "Renamed Server"},
	})
	dialogs, err = tc.GetDialogs(PaginationOpts{})
	if err != nil {
		t.Fatal(err)
	}
	if dialogs[0].Title != "Renamed Server" {
		t.Errorf("server dialog title after rename = %q, want Renamed Server", dialogs[0].Title)
	}
}

// TestTeamSpeakServerDialogFallsBackWithoutName: until an initserver
// arrives (or for servers that never push a name), the historical
// label must stay — no regression to an empty title.
func TestTeamSpeakServerDialogFallsBackWithoutName(t *testing.T) {
	tc := &TeamSpeakCore{authed: true}
	dialogs, err := tc.GetDialogs(PaginationOpts{})
	if err != nil {
		t.Fatal(err)
	}
	if len(dialogs) == 0 {
		t.Fatal("no dialogs")
	}
	if dialogs[0].Title != "Server Chat" {
		t.Errorf("server dialog title = %q, want the fallback %q", dialogs[0].Title, "Server Chat")
	}
}
