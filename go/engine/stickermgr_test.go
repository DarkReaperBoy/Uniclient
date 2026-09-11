package engine

// Sticker manager engine surface (slice 139): the lightweight set-listing
// fetcher (installed + archived in one call) and the archive toggle pass
// through to cores that implement them; plain cores report unsupported.

import (
	"testing"

	"uniclient/cores"
)

// stickerMgrStub records calls and serves canned data.
type stickerMgrStub struct {
	cores.StubCore
	summaries []cores.StickerPackSummary
	listErr   error
	archived  [][3]any // setID, accessHash, archived
	archErr   error
}

func (s *stickerMgrStub) GetStickerSetSummaries() ([]cores.StickerPackSummary, error) {
	return s.summaries, s.listErr
}

func (s *stickerMgrStub) ArchiveStickerSet(setID, accessHash int64, archived bool) error {
	s.archived = append(s.archived, [3]any{setID, accessHash, archived})
	return s.archErr
}

func TestGetStickerSetSummariesPassthrough(t *testing.T) {
	e := newTestEngine(t)
	want := []cores.StickerPackSummary{
		{SetID: 1, Title: "Kept", Installed: true},
		{SetID: 2, Title: "Boxed", Archived: true},
	}
	e.accounts = map[string]*Account{
		"tg":  {ID: "tg", Core: &stickerMgrStub{summaries: want}},
		"irc": {ID: "irc", Core: plainStub{}},
	}
	got, err := e.GetStickerSetSummaries("tg")
	if err != nil || len(got) != 2 || got[1].Title != "Boxed" {
		t.Fatalf("GetStickerSetSummaries = %+v err=%v", got, err)
	}
	if _, err := e.GetStickerSetSummaries("irc"); err == nil {
		t.Fatal("plain core reported sticker set support")
	}
	if _, err := e.GetStickerSetSummaries("missing"); err == nil {
		t.Fatal("missing account reported support")
	}
}

func TestArchiveStickerSetPassthrough(t *testing.T) {
	e := newTestEngine(t)
	stub := &stickerMgrStub{}
	e.accounts = map[string]*Account{
		"tg":  {ID: "tg", Core: stub},
		"irc": {ID: "irc", Core: plainStub{}},
	}
	if err := e.ArchiveStickerSet("tg", 42, 4242, true); err != nil {
		t.Fatalf("archive: %v", err)
	}
	if err := e.ArchiveStickerSet("tg", 42, 4242, false); err != nil {
		t.Fatalf("unarchive: %v", err)
	}
	if len(stub.archived) != 2 {
		t.Fatalf("calls = %d, want 2", len(stub.archived))
	}
	if stub.archived[0][0] != int64(42) || stub.archived[0][1] != int64(4242) || stub.archived[0][2] != true {
		t.Fatalf("first call = %+v", stub.archived[0])
	}
	if stub.archived[1][2] != false {
		t.Fatalf("second call = %+v", stub.archived[1])
	}
	if err := e.ArchiveStickerSet("irc", 1, 1, true); err == nil {
		t.Fatal("plain core reported archive support")
	}
	if err := e.ArchiveStickerSet("missing", 1, 1, true); err == nil {
		t.Fatal("missing account reported archive support")
	}
}
