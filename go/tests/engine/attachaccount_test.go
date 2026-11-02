package tests

import (
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	. "uniclient/engine"

	"uniclient/cores"
	"uniclient/utils"
)

type attachCapsStub struct {
	cores.StubCore
}

func (attachCapsStub) Capabilities() []string { return []string{"send", "react"} }

func TestNewEngineAppliesConfigAndDefaults(t *testing.T) {
	dir := t.TempDir()
	v, err := utils.CreateVault(filepath.Join(dir, "vault.db"), "test")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { v.Close() })

	saveDeleted, saveHistory, saveForBots := false, false, true
	cfg := utils.DefaultConfig()
	cfg.AyuSaveDeleted = &saveDeleted
	cfg.AyuSaveHistory = &saveHistory
	cfg.AyuSaveForBots = &saveForBots
	cfgPtr := &cfg

	e := New(nil, v, cfgPtr)
	if e.GetConfig() != cfgPtr {
		t.Fatal("GetConfig must return the config handed to New")
	}
	if e.Vault() != v {
		t.Fatal("Vault must return the vault handed to New")
	}
	gd, gh, gb := e.GetAntiRecallSettings()
	if gd || gh || !gb {
		t.Fatalf("anti-recall flags = %v/%v/%v, want false/false/true (config wins)", gd, gh, gb)
	}

	plain := New(nil, nil, nil)
	gd, gh, gb = plain.GetAntiRecallSettings()
	if !gd || !gh || gb {
		t.Fatalf("default anti-recall flags = %v/%v/%v, want true/true/false (production defaults)", gd, gh, gb)
	}
}

func TestAttachAccountContract(t *testing.T) {
	e := New(nil, nil, nil)
	if err := e.AttachAccount("", "telegram", nil); err == nil {
		t.Fatal("empty id must error")
	}

	var want cores.Core = attachCapsStub{}
	if err := e.AttachAccount("tg", "telegram", want); err != nil {
		t.Fatal(err)
	}
	if err := e.AttachAccount("tg", "telegram", nil); err == nil {
		t.Fatal("duplicate id must error")
	}
	if got := e.GetAccountCore("tg"); got != want {
		t.Fatalf("GetAccountCore = %v, want the attached core", got)
	}
	if got := e.GetAccountCore("missing"); got != nil {
		t.Fatalf("GetAccountCore(missing) = %v, want nil", got)
	}

	caps := e.AccountCapabilities("tg")
	if len(caps) != 2 || caps[0] != "send" || caps[1] != "react" {
		t.Fatalf("AccountCapabilities = %v, want [send react]", caps)
	}

	if err := e.AttachAccount("bare", "irc", nil); err != nil {
		t.Fatal(err)
	}
	if got := e.GetAccountCore("bare"); got != nil {
		t.Fatalf("coreless attach must leave nil core, got %v", got)
	}
	if got := e.AccountCapabilities("bare"); got != nil {
		t.Fatalf("AccountCapabilities on coreless account = %v, want nil", got)
	}
}

func TestAttachAccountListShape(t *testing.T) {
	e := New(nil, nil, nil)
	if err := e.AttachAccount("tg", "telegram", nil); err != nil {
		t.Fatal(err)
	}
	if err := e.AttachAccount("irc", "irc", nil); err != nil {
		t.Fatal(err)
	}
	list := e.ListAccounts()
	if len(list) != 2 {
		t.Fatalf("ListAccounts len = %d, want 2", len(list))
	}
	if list[0].ID != "tg" || list[0].Platform != "telegram" {
		t.Fatalf("first account = %s/%s, want tg/telegram", list[0].ID, list[0].Platform)
	}
	if list[1].ID != "irc" || list[1].Platform != "irc" {
		t.Fatalf("second account = %s/%s, want irc/irc", list[1].ID, list[1].Platform)
	}
	if list[0].ConnState != int(ConnConnected) {
		t.Fatalf("attached ConnState = %d, want connected", list[0].ConnState)
	}
}

func TestReplaceAccountCoreContract(t *testing.T) {
	e := New(nil, nil, nil)
	if err := e.ReplaceAccountCore("a1", nil); err == nil {
		t.Fatal("missing account must error")
	}

	var first cores.Core = attachCapsStub{}
	if err := e.AttachAccount("a1", "telegram", first); err != nil {
		t.Fatal(err)
	}
	if got := e.GetAccountCore("a1"); got != first {
		t.Fatalf("GetAccountCore = %v, want first core", got)
	}

	var second cores.Core = cores.StubCore{}
	if err := e.ReplaceAccountCore("a1", second); err != nil {
		t.Fatal(err)
	}
	if got := e.GetAccountCore("a1"); got != second {
		t.Fatalf("GetAccountCore = %v, want replaced core", got)
	}
	if caps := e.AccountCapabilities("a1"); len(caps) != 0 {
		t.Fatalf("AccountCapabilities after replace = %v, want stub's nil", caps)
	}

	if err := e.ReplaceAccountCore("a1", nil); err != nil {
		t.Fatal(err)
	}
	if got := e.GetAccountCore("a1"); got != nil {
		t.Fatalf("GetAccountCore after nil replace = %v, want nil", got)
	}
	list := e.ListAccounts()
	if len(list) != 1 || list[0].ID != "a1" {
		t.Fatalf("replace must keep the account registered, got %v", list)
	}
}

func TestAttachAccountConcurrent(t *testing.T) {
	e := New(nil, nil, nil)
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			id := "acc" + string(rune('0'+i))
			if err := e.AttachAccount(id, "telegram", attachCapsStub{}); err != nil {
				t.Error(err)
			}
		}(i)
	}
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < 50; j++ {
				e.ListAccounts()
				e.GetAccountCore("acc0")
			}
		}()
	}
	wg.Wait()
	if len(e.ListAccounts()) != 8 {
		t.Fatalf("ListAccounts len = %d, want 8", len(e.ListAccounts()))
	}

	var wins int64
	for i := 0; i < 16; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := e.AttachAccount("race", "telegram", nil); err == nil {
				atomic.AddInt64(&wins, 1)
			}
		}()
	}
	wg.Wait()
	if wins != 1 {
		t.Fatalf("same-id attach wins = %d, want exactly 1", wins)
	}
}
