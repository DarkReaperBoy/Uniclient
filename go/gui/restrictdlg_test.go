package gui

import (
	"testing"
	"time"

	"uniclient/engine"
)

// Restrict/ban boxes (slice 191, tdesktop RestrictParticipantBox + the ban
// box): pure logic — duration ladder, until-date math, the allowed↔banned
// inversion, initial-rights resolution, and the permission-row table.
// Layout is verified by compile + review (repo discipline).

func TestRestrictDurationPresets(t *testing.T) {
	want := []struct {
		label string
		secs  int
	}{
		{"Forever", 0},
		{"1 hour", 3600},
		{"8 hours", 8 * 3600},
		{"2 days", 2 * 86400},
		{"1 week", 604800},
		{"1 month", 30 * 86400},
		{"3 months", 3 * 30 * 86400},
		{"6 months", 6 * 30 * 86400},
		{"1 year", 365 * 86400},
	}
	if len(restrictDurations) != len(want) {
		t.Fatalf("restrictDurations len = %d, want %d", len(restrictDurations), len(want))
	}
	for i, w := range want {
		if restrictDurations[i].label != w.label || restrictDurations[i].secs != w.secs {
			t.Errorf("restrictDurations[%d] = %q/%d, want %q/%d", i,
				restrictDurations[i].label, restrictDurations[i].secs, w.label, w.secs)
		}
	}
}

func TestBanUntilDate(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	if got := banUntilDate(now, 0); got != 0 {
		t.Errorf("forever untilDate = %d, want 0 (Telegram forever)", got)
	}
	if got := banUntilDate(now, 3600); got != int(now.Unix())+3600 {
		t.Errorf("1h untilDate = %d, want %d", got, int(now.Unix())+3600)
	}
}

func TestRestrictPermissionRows(t *testing.T) {
	rows := restrictPermissionRows()
	if len(rows) != 15 {
		t.Fatalf("permission rows = %d, want 15 (one per DefaultBannedRights right)", len(rows))
	}
	seen := map[string]bool{}
	for _, r := range rows {
		if r.label == "" {
			t.Error("empty permission label")
		}
		seen[r.field] = true
	}
	for _, f := range []string{"SendPlain", "SendPhotos", "SendVideos", "SendRoundvideos",
		"SendAudios", "SendVoices", "SendDocs", "SendStickers", "EmbedLinks", "SendPolls",
		"InviteUsers", "PinMessages", "ManageTopics", "ChangeInfo", "EditRank"} {
		if !seen[f] {
			t.Errorf("permission rows lack field %s", f)
		}
	}
}

func TestBannedRightsFromAllowed(t *testing.T) {
	// The GUI tracks ALLOWED switches; the wire wants BANNED flags.
	allowed := map[string]bool{
		"SendPlain":  false, // banned
		"SendPhotos": true,
		"SendDocs":   false, // banned
	}
	br := bannedRightsFromAllowed(allowed)
	if !br.SendPlain || br.SendPhotos || !br.SendDocs {
		t.Errorf("inversion wrong: %+v", br)
	}
	if br.SendVideos || br.SendStickers || br.ChangeInfo {
		t.Errorf("unspecified fields must default to allowed: %+v", br)
	}
}

func TestInitialRestrictRights(t *testing.T) {
	// Fresh member (no cached rights): all allowed.
	br := initialRestrictRights(engine.MemberInfo{Role: "member"})
	if br.SendPlain || br.SendStickers || br.ChangeInfo {
		t.Errorf("fresh member should start all-allowed: %+v", br)
	}

	// Restricted member: their cached rights load verbatim.
	cur := &engine.DefaultBannedRights{SendPlain: true, SendPolls: true}
	br = initialRestrictRights(engine.MemberInfo{Role: "restricted", BannedRights: cur})
	if !br.SendPlain || !br.SendPolls || br.SendStickers {
		t.Errorf("restricted member should load current rights: %+v", br)
	}
}
