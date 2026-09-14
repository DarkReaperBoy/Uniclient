package engine

import (
	"testing"

	"uniclient/cores"
)

// Profile music (slice 206): the engine surface — per-(account, peer)
// ordered track cache fed by the core fetcher, own-playlist mutations
// (save/remove/reorder) forwarded with cache + event updates, the
// own-ID gate for the bubble menu, and playback by document ID.

// profileMusicStub: a core exposing the slice-206 surface, recording
// mutations through pointer logs (accounts hold cores by value).
type profileMusicStub struct {
	cores.StubCore
	selfID string
	tracks map[string][]cores.MusicTrackInfo // peerID → playlist
	count  map[string]int

	fetches   *[]string // peerIDs fetched
	saves     *[][2]string
	unsaves   *[]string
	ownIDs    *[]string
	ownHashes *[]int64
}

func newProfileMusicStub() profileMusicStub {
	return profileMusicStub{
		tracks:    map[string][]cores.MusicTrackInfo{},
		count:     map[string]int{},
		fetches:   &[]string{},
		saves:     &[][2]string{},
		unsaves:   &[]string{},
		ownIDs:    &[]string{},
		ownHashes: &[]int64{},
	}
}

func (s profileMusicStub) SelfUserID() string { return s.selfID }

func (s profileMusicStub) GetProfileMusic(peerID string) ([]cores.MusicTrackInfo, int, error) {
	*s.fetches = append(*s.fetches, peerID)
	tr := s.tracks[peerID]
	return append([]cores.MusicTrackInfo(nil), tr...), s.count[peerID], nil
}

func (s profileMusicStub) SaveProfileMusicDoc(track, after cores.MusicTrackInfo, unsave bool) error {
	if unsave {
		*s.unsaves = append(*s.unsaves, track.DocID)
		var kept []cores.MusicTrackInfo
		for _, t := range s.tracks[s.selfID] {
			if t.DocID != track.DocID {
				kept = append(kept, t)
			}
		}
		s.tracks[s.selfID] = kept
		var ids []string
		for _, id := range *s.ownIDs {
			if id != track.DocID {
				ids = append(ids, id)
			}
		}
		*s.ownIDs = ids
		return nil
	}
	*s.saves = append(*s.saves, [2]string{track.DocID, after.DocID})
	// Server semantics: plain save moves to top; after moves after `after`.
	var kept []cores.MusicTrackInfo
	for _, t := range s.tracks[s.selfID] {
		if t.DocID != track.DocID {
			kept = append(kept, t)
		}
	}
	if after.DocID == "" {
		s.tracks[s.selfID] = append([]cores.MusicTrackInfo{track}, kept...)
	} else {
		out := make([]cores.MusicTrackInfo, 0, len(kept)+1)
		for _, t := range kept {
			out = append(out, t)
			if t.DocID == after.DocID {
				out = append(out, track)
			}
		}
		s.tracks[s.selfID] = out
	}
	// The server's own-ID list gains the saved doc.
	has := false
	for _, id := range *s.ownIDs {
		if id == track.DocID {
			has = true
		}
	}
	if !has {
		*s.ownIDs = append([]string{track.DocID}, *s.ownIDs...)
	}
	return nil
}

func (s profileMusicStub) GetOwnSavedMusicIDs(hash int64) ([]string, bool, error) {
	*s.ownHashes = append(*s.ownHashes, hash)
	ids := *s.ownIDs
	if hash != 0 && len(ids) > 0 {
		sum := int64(0)
		for _, id := range ids {
			sum += parseInt64(id)
		}
		if sum == hash {
			return nil, false, nil
		}
	}
	out := make([]string, len(ids))
	copy(out, ids)
	return out, true, nil
}

func newProfileMusicEngine(t *testing.T) *Engine {
	t.Helper()
	e := newTestEngine(t)
	if _, err := e.db.Exec(
		`INSERT OR IGNORE INTO accounts (id, platform, display_name, sort_order, created_at)
                 VALUES ('tg', 'telegram', 'Test', 0, 0)`); err != nil {
		t.Fatal(err)
	}
	return e
}

func TestProfileMusicSupported(t *testing.T) {
	e := newProfileMusicEngine(t)
	e.accounts = map[string]*Account{
		"tg":  {ID: "tg", Core: newProfileMusicStub()},
		"irc": {ID: "irc", Core: plainStub{}},
	}
	if !e.ProfileMusicSupported("tg") {
		t.Error("profile-music core reported unsupported")
	}
	if e.ProfileMusicSupported("irc") {
		t.Error("plain stub must not report profile-music support")
	}
	if e.ProfileMusicSupported("missing") {
		t.Error("missing account reported supported")
	}
}

func TestGetProfileMusicFeedsColdCache(t *testing.T) {
	e := newProfileMusicEngine(t)
	st := newProfileMusicStub()
	st.selfID = "42"
	st.tracks["7"] = []cores.MusicTrackInfo{
		{DocID: "7001", Title: "Nightcall", Performer: "Kavinsky", Duration: 257, AccessHash: 5, FileRefB64: "AAAA", Size: 100, MimeType: "audio/mpeg", FileName: "a.mp3"},
		{DocID: "7002", Title: "Rampage", Performer: "Aphex Twin", Duration: 200, AccessHash: 6, FileRefB64: "AAAB", Size: 200, MimeType: "audio/mpeg"},
	}
	st.count["7"] = 2
	e.accounts = map[string]*Account{"tg": {ID: "tg", Core: st}}

	tracks, err := e.GetProfileMusic("tg", "7")
	if err != nil {
		t.Fatal(err)
	}
	if len(tracks) != 2 {
		t.Fatalf("tracks = %d, want 2", len(tracks))
	}
	if tracks[0].DocID != "7001" || tracks[0].Position != 0 || tracks[1].Position != 1 {
		t.Errorf("order/positions wrong: %+v", tracks)
	}
	if tracks[0].FileRefB64 != "AAAA" || tracks[0].AccessHash != 5 {
		t.Errorf("download fields lost: %+v", tracks[0])
	}
	// Second read is cache-only (no extra fetch).
	n := len(*st.fetches)
	if _, err := e.GetProfileMusic("tg", "7"); err != nil {
		t.Fatal(err)
	}
	if len(*st.fetches) != n {
		t.Error("warm cache re-fetched from the server")
	}
}

func TestGetProfileMusicEmptyHidesSection(t *testing.T) {
	e := newProfileMusicEngine(t)
	st := newProfileMusicStub()
	st.selfID = "42"
	e.accounts = map[string]*Account{"tg": {ID: "tg", Core: st}}
	tracks, err := e.GetProfileMusic("tg", "7")
	if err != nil {
		t.Fatal(err)
	}
	if len(tracks) != 0 {
		t.Errorf("empty playlist must be an honest empty state, got %d", len(tracks))
	}
}

func TestSaveToProfileMusic(t *testing.T) {
	e := newProfileMusicEngine(t)
	st := newProfileMusicStub()
	st.selfID = "42"
	st.tracks["42"] = []cores.MusicTrackInfo{{DocID: "7000", Title: "Seed"}}
	*st.ownIDs = []string{"7000"}
	e.accounts = map[string]*Account{"tg": {ID: "tg", Core: st}}

	track := MusicTrack{DocID: "7001", Title: "Nightcall", AccessHash: 5, FileRefB64: "AAAA", MimeType: "audio/mpeg", FileName: "n.mp3", Duration: 257}
	if err := e.SaveToProfileMusic("tg", track); err != nil {
		t.Fatal(err)
	}
	if len(*st.saves) != 1 || (*st.saves)[0] != [2]string{"7001", ""} {
		t.Errorf("save call = %+v, want plain add 7001", *st.saves)
	}
	// Own playlist cache refreshed: the new track is at the top.
	ids := e.OwnProfileMusicCached("tg")
	if len(ids) != 2 || !ids["7001"] || !ids["7000"] {
		t.Errorf("own IDs after save = %v", ids)
	}
	// The own-profile cache row exists too (panel shows the track).
	tracks, err := e.GetProfileMusic("tg", "42")
	if err != nil {
		t.Fatal(err)
	}
	if len(tracks) != 2 || tracks[0].DocID != "7001" {
		t.Errorf("own playlist cache = %+v", tracks)
	}
}

func TestRemoveProfileMusic(t *testing.T) {
	e := newProfileMusicEngine(t)
	st := newProfileMusicStub()
	st.selfID = "42"
	st.tracks["42"] = []cores.MusicTrackInfo{{DocID: "7001"}, {DocID: "7002"}}
	*st.ownIDs = []string{"7001", "7002"}
	e.accounts = map[string]*Account{"tg": {ID: "tg", Core: st}}
	if _, err := e.GetProfileMusic("tg", "42"); err != nil {
		t.Fatal(err)
	}

	if err := e.RemoveProfileMusic("tg", "7002"); err != nil {
		t.Fatal(err)
	}
	if len(*st.unsaves) != 1 || (*st.unsaves)[0] != "7002" {
		t.Errorf("unsave call = %v", *st.unsaves)
	}
	if ids := e.OwnProfileMusicCached("tg"); len(ids) != 1 || !ids["7001"] {
		t.Errorf("own IDs after remove = %v", ids)
	}
}

func TestReorderProfileMusic(t *testing.T) {
	e := newProfileMusicEngine(t)
	st := newProfileMusicStub()
	st.selfID = "42"
	st.tracks["42"] = []cores.MusicTrackInfo{
		{DocID: "7001"}, {DocID: "7002"}, {DocID: "7003"},
	}
	e.accounts = map[string]*Account{"tg": {ID: "tg", Core: st}}
	if _, err := e.GetProfileMusic("tg", "42"); err != nil {
		t.Fatal(err)
	}

	// Move 7003 after 7001: expect [7001, 7003, 7002].
	if err := e.ReorderProfileMusic("tg", "7003", "7001"); err != nil {
		t.Fatal(err)
	}
	if len(*st.saves) != 1 || (*st.saves)[0] != [2]string{"7003", "7001"} {
		t.Fatalf("reorder call = %v", *st.saves)
	}
	tracks, err := e.GetProfileMusic("tg", "42")
	if err != nil {
		t.Fatal(err)
	}
	if len(tracks) != 3 || tracks[0].DocID != "7001" || tracks[1].DocID != "7003" || tracks[2].DocID != "7002" {
		t.Errorf("reordered cache = %v %v %v", tracks[0].DocID, tracks[1].DocID, tracks[2].DocID)
	}
}

func TestReorderProfileMusicEdgeCases(t *testing.T) {
	e := newProfileMusicEngine(t)
	st := newProfileMusicStub()
	st.selfID = "42"
	st.tracks["42"] = []cores.MusicTrackInfo{{DocID: "7001"}, {DocID: "7002"}}
	e.accounts = map[string]*Account{"tg": {ID: "tg", Core: st}}
	if _, err := e.GetProfileMusic("tg", "42"); err != nil {
		t.Fatal(err)
	}
	// Same position no-op: after = the predecessor already.
	if err := e.ReorderProfileMusic("tg", "7002", "7001"); err != nil {
		t.Fatal(err)
	}
	tracks, _ := e.GetProfileMusic("tg", "42")
	if tracks[0].DocID != "7001" || tracks[1].DocID != "7002" {
		t.Errorf("no-op reorder changed order: %v %v", tracks[0].DocID, tracks[1].DocID)
	}
	// Unknown doc / unknown after → honest errors, no mutation.
	if err := e.ReorderProfileMusic("tg", "9999", "7001"); err == nil {
		t.Error("unknown doc must error")
	}
	if err := e.ReorderProfileMusic("tg", "7001", "9999"); err == nil {
		t.Error("unknown after must error")
	}
}

func TestOwnProfileMusicHashGating(t *testing.T) {
	e := newProfileMusicEngine(t)
	st := newProfileMusicStub()
	st.selfID = "42"
	*st.ownIDs = []string{"10", "20"}
	e.accounts = map[string]*Account{"tg": {ID: "tg", Core: st}}

	if _, err := e.RefreshOwnProfileMusic("tg"); err != nil {
		t.Fatal(err)
	}
	if len(*st.ownHashes) != 1 || (*st.ownHashes)[0] != 0 {
		t.Fatalf("first refresh hash = %v, want 0 (cold)", *st.ownHashes)
	}
	// Second refresh passes the sum hash; the stub answers notModified.
	if _, err := e.RefreshOwnProfileMusic("tg"); err != nil {
		t.Fatal(err)
	}
	if len(*st.ownHashes) != 2 || (*st.ownHashes)[1] != 30 {
		t.Fatalf("second refresh hash = %v, want 30 (10+20)", *st.ownHashes)
	}
	// Cached read needs no RPC.
	before := len(*st.ownHashes)
	ids := e.OwnProfileMusicCached("tg")
	if len(ids) != 2 || !ids["10"] || !ids["20"] {
		t.Errorf("cached IDs = %v", ids)
	}
	if len(*st.ownHashes) != before {
		t.Error("cached read triggered an RPC")
	}
}

func TestProfileMusicSelfPeerGate(t *testing.T) {
	// Only user peers have playlists; the engine surface is invoked with
	// the peer ID verbatim (the core does the InputPeerUser check).
	e := newProfileMusicEngine(t)
	st := newProfileMusicStub()
	st.selfID = "42"
	st.tracks["-1001234"] = nil // channel-ish peer: core would reject
	e.accounts = map[string]*Account{"tg": {ID: "tg", Core: st}}
	if _, err := e.GetProfileMusic("tg", "-1001234"); err != nil {
		t.Fatalf("engine must forward non-user peers to the core gate: %v", err)
	}
}
