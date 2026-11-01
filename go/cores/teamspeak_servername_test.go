package cores

import "testing"

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
