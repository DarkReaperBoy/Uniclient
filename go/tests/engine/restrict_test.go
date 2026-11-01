package tests

import (
	"testing"
	. "uniclient/engine"

	"uniclient/cores"
)

type fakeRestrictCore struct {
	cores.StubCore
	banCalls    [][3]interface{}
	restrictErr error
}

func (f *fakeRestrictCore) BanMemberUntil(chatID, userID string, untilDate int) error {
	f.banCalls = append(f.banCalls, [3]interface{}{chatID, userID, untilDate})
	return f.restrictErr
}

func TestBanMemberUntil(t *testing.T) {
	e := newTestEngine(t)
	fc := &fakeRestrictCore{}
	e.ForTestSetAccounts(map[string]*Account{"a1": {ID: "a1", Core: fc}})

	if err := e.BanMemberUntil("a1", "g1", "7", 3600); err != nil {
		t.Fatal(err)
	}
	if len(fc.banCalls) != 1 {
		t.Fatalf("ban calls = %d, want 1", len(fc.banCalls))
	}
	got := fc.banCalls[0]
	if got[0] != "g1" || got[1] != "7" || got[2].(int) != 3600 {
		t.Errorf("BanMemberUntil args = %v, want g1/7/3600", got)
	}

	if err := e.BanMemberUntil("nope", "g1", "7", 3600); err == nil {
		t.Error("missing account must error")
	}
	e.ForTestSetAccounts(map[string]*Account{"a1": {ID: "a1", Core: &cores.StubCore{}}})
	if err := e.BanMemberUntil("a1", "g1", "7", 3600); err == nil {
		t.Error("unsupported core must error")
	}
}

func TestMemberBannedRightsMirror(t *testing.T) {
	ex := cores.ParticipantExtra{
		CanRestrict: true,
		BannedRights: &cores.DefaultBannedRights{
			SendPlain:    true,
			SendStickers: true,
			EmbedLinks:   true,
		},
		BannedUntil: 3600,
	}
	mi := MemberFromExtra("u9", "restricted", ex)
	if mi.BannedRights == nil || !mi.BannedRights.SendPlain || !mi.BannedRights.SendStickers || mi.BannedRights.SendPhotos {
		t.Errorf("banned rights mirror = %+v", mi.BannedRights)
	}
	if mi.BannedUntil != 3600 {
		t.Errorf("banned until = %d, want 3600", mi.BannedUntil)
	}

	mi2 := MemberFromExtra("u8", "member", cores.ParticipantExtra{})
	if mi2.BannedRights != nil {
		t.Errorf("member without rights should mirror nil, got %+v", mi2.BannedRights)
	}
}
