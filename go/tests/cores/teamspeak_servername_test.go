package tests

import (
	"testing"
	"time"

	. "uniclient/cores"
)

func TestTeamSpeakInitserverStoresAndSurfacesServerName(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{ServerName: "Arctic Test Server"})

	if got := core.ServerName(); got != "Arctic Test Server" {
		t.Errorf("ServerName = %q, want %q — initserver not ingested through the real wire", got, "Arctic Test Server")
	}
	dialogs, err := core.GetDialogs(PaginationOpts{})
	if err != nil {
		t.Fatal(err)
	}
	if len(dialogs) == 0 || dialogs[0].ID != "server" {
		t.Fatalf("dialogs = %+v, want the server entry first", dialogs)
	}
	if dialogs[0].Title != "Arctic Test Server" {
		t.Errorf("server dialog title = %q, want the virtualserver_name from initserver — a TS server's own name never reaches the UI (B-16)", dialogs[0].Title)
	}

	srv.Push("initserver virtualserver_name=" + TsEscape("Renamed Server"))
	deadline := time.Now().Add(2 * time.Second)
	for {
		dialogs, err = core.GetDialogs(PaginationOpts{})
		if err != nil {
			t.Fatal(err)
		}
		if dialogs[0].Title == "Renamed Server" {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("server dialog title never became %q through the real wire, still %q", "Renamed Server", dialogs[0].Title)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func TestTeamSpeakServerDialogFallsBackWithoutName(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, _ := newScriptedTSCore(t, tsScriptedConfig{OmitServerName: true})
	dialogs, err := core.GetDialogs(PaginationOpts{})
	if err != nil {
		t.Fatal(err)
	}
	if len(dialogs) == 0 {
		t.Fatal("no dialogs")
	}
	if dialogs[0].Title != "Server Chat" {
		t.Errorf("server dialog title = %q, want the fallback %q when initserver carries no virtualserver_name", dialogs[0].Title, "Server Chat")
	}
}
