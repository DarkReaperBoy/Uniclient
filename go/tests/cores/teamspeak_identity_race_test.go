package tests

import (
	"sync"
	"testing"
	"time"

	. "uniclient/cores"
	"uniclient/utils"
)

func TestHandshakeClientIDWriteDoesNotRaceTheReceiveLoop(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{
		ServerName:    "Flooded HQ",
		ClientID:      500,
		FloodCommands: 120,
	})

	if got := core.ServerName(); got != "Flooded HQ" {
		t.Errorf("ServerName = %q, want %q — the journey must complete through the flood", got, "Flooded HQ")
	}

	deadline := time.Now().Add(3 * time.Second)
	for srv.AckedCount() < 120 && time.Now().Before(deadline) {
		time.Sleep(20 * time.Millisecond)
	}
	if got := srv.AckedCount(); got < 120 {
		t.Fatalf("server saw %d acks, want >= 120 — every flooded command packet must be acked by the receive loop (the clientID read path)", got)
	}

	for i := uint16(1); i <= 100; i++ {
		srv.PushPing(i)
		if i%20 == 0 {
			time.Sleep(time.Millisecond)
		}
	}
	deadline = time.Now().Add(2 * time.Second)
	for srv.PongCount() < 100 && time.Now().Before(deadline) {
		time.Sleep(20 * time.Millisecond)
	}
	if got := srv.PongCount(); got < 100 {
		t.Fatalf("server saw %d pongs, want 100 — every ping must be answered (the pong path reads clientID too)", got)
	}
}

func TestHandshakeMyClientIDWriteDoesNotRaceReceiveHandlers(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })

	srv := startTSScriptedServer(t, tsScriptedConfig{ServerName: "Hammered HQ", ClientID: 42})
	store := utils.NewSessionStore(newTestVaultSimple(t, t.TempDir()), "ts-hammer")
	core := NewTeamSpeakCore(store)
	t.Cleanup(func() { _ = core.Logout() })

	const hammers = 100
	errs := make(chan error, hammers)
	var wg sync.WaitGroup
	for i := 0; i < hammers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := core.SendMessage("bogus", OutgoingMessage{Text: "x"})
			errs <- err
		}()
	}

	if err := core.Authenticate(AuthConfig{Mode: AuthModeUser, Extra: map[string]string{
		"server_address": srv.Addr(),
		"nickname":       "alice",
	}}); err != nil {
		t.Fatalf("Authenticate: %v", err)
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err == nil {
			t.Fatal("a hammer SendMessage unexpectedly succeeded — it must fail on the invalid chat ID after auth completes")
		}
	}

	if got := core.ForTestMyClientID(); got != 42 {
		t.Fatalf("myClientID = %d, want 42 (the initserver write site must be live)", got)
	}
}
