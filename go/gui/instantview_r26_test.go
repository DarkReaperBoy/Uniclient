package gui

import (
	"encoding/json"
	"errors"
	"testing"
)

// ivPageJSON builds a minimal parseable IV page payload for a URL.
func ivPageJSON(u string) []byte {
	raw, _ := json.Marshal(map[string]interface{}{
		"url":    u,
		"title":  u,
		"blocks": []interface{}{plainRT("body")},
	})
	return raw
}

// ivHead returns the current installed reader head (test helper).
func ivHead(a *App) *ivState {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.iv
}

// TestIVLandRelatedStaleGeneration pins R26 (updated for R46's copy-on-write
// landing): a related-article fetch captures the reader session's openID AND
// the navigation generation; closing/reopening the reader (openID) or
// backing out / navigating again (generation) retires a straggler fetch —
// it may never push itself (or a wrong page) onto the history. Pre-R26, the
// only guard was `!cur.loading`: back-during-fetch rearmed the flag on the
// NEXT navigation and the straggler sailed through, corrupting the back
// stack (user backs from C and lands on a page they never opened).
// R46 note: landing installs a FRESH head (the frame-held state is never
// mutated in place), so the assertions observe the installed head.
func TestIVLandRelatedStaleGeneration(t *testing.T) {
	a := &App{}
	root := &ivPage{URL: "https://telegra.ph/root", Blocks: []ivBlock{{Type: "paragraph"}}}
	st := &ivState{accountID: "acc", url: root.URL, page: root, gen: 5, openID: 7}
	a.mu.Lock()
	a.iv = st
	a.mu.Unlock()

	// Current-generation fetch lands: new page shown, old one pushed.
	landed, fb := a.ivLandRelated(7, 5, ivPageJSON("https://telegra.ph/b"), nil)
	if !landed || fb {
		t.Fatalf("current-generation fetch must land (landed=%v fallback=%v)", landed, fb)
	}
	head := ivHead(a)
	if head == nil || head == st {
		t.Fatal("landing must install a fresh head (R46 copy-on-write)")
	}
	if head.page.URL != "https://telegra.ph/b" || len(head.hist) != 1 || head.hist[0] != root {
		t.Fatalf("landing must push the old page and show the new one: url=%s hist=%d", head.page.URL, len(head.hist))
	}
	// The replaced head stays frozen (frame safety) — the R26 observable
	// (st.page) is now observed on the installed head instead.
	if st.page != root || len(st.hist) != 0 {
		t.Fatal("the replaced head must stay frozen")
	}

	// Stale generation (user navigated again mid-flight): dropped whole.
	a.updateIV(func(cur *ivState) bool { cur.gen = 6; return true }) // simulate the navigation
	if landed, _ := a.ivLandRelated(7, 5, ivPageJSON("https://telegra.ph/c"), nil); landed {
		t.Fatal("stale-generation fetch must be dropped (R26)")
	}
	head = ivHead(a)
	if head.page.URL != "https://telegra.ph/b" || len(head.hist) != 1 {
		t.Fatal("a stale fetch must not touch the history")
	}

	// Replaced session (overlay closed / reopened elsewhere): dropped whole.
	a.mu.Lock()
	a.iv = nil
	a.mu.Unlock()
	if landed, _ := a.ivLandRelated(7, 6, ivPageJSON("https://telegra.ph/c"), nil); landed {
		t.Fatal("fetch against a closed reader must be dropped")
	}

	// Current-generation error lands as the reader's error state (toast path).
	a.mu.Lock()
	a.iv = &ivState{accountID: "acc", gen: 6, openID: 7, loading: true}
	a.mu.Unlock()
	landed, fb = a.ivLandRelated(7, 6, nil, errors.New("boom"))
	if !landed || fb {
		t.Fatalf("current-generation error must land (landed=%v fallback=%v)", landed, fb)
	}
	head = ivHead(a)
	if head.loading || head.err != "boom" {
		t.Fatalf("error landing must clear loading and set err: loading=%v err=%q", head.loading, head.err)
	}

	// Current-generation unparseable payload lands with the browser fallback.
	landed, fb = a.ivLandRelated(7, 6, []byte("not-json"), nil)
	if !landed || !fb {
		t.Fatalf("unparseable page at the current generation must land with the browser fallback (landed=%v fallback=%v)", landed, fb)
	}

	// A foreign session's fetch (openID mismatch): dropped whole.
	if landed, _ := a.ivLandRelated(9, 6, ivPageJSON("https://telegra.ph/d"), nil); landed {
		t.Fatal("a foreign-session fetch must be dropped (R46 openID guard)")
	}
}

// TestIVBackBumpsGeneration pins the other half of R26's wiring (updated
// for R46): ivBack bumps the generation on the INSTALLED HEAD (it installs
// a fresh head instead of mutating), so a related fetch still in flight
// when the user went back must fail the landing gate.
func TestIVBackBumpsGeneration(t *testing.T) {
	a := &App{}
	root := &ivPage{URL: "https://telegra.ph/root", Blocks: []ivBlock{{Type: "paragraph"}}}
	other := &ivPage{URL: "https://telegra.ph/other", Blocks: []ivBlock{{Type: "paragraph"}}}
	st := &ivState{accountID: "acc", url: other.URL, page: other, hist: []*ivPage{root}, gen: 3, openID: 7}
	a.mu.Lock()
	a.iv = st
	a.mu.Unlock()

	pre := st.gen
	a.ivBack() // pops to root, stays open
	head := ivHead(a)
	if head == nil || head == st {
		t.Fatal("ivBack must install a fresh head (R46 copy-on-write)")
	}
	if head.gen <= pre {
		t.Fatalf("ivBack must bump the generation (pre=%d post=%d)", pre, head.gen)
	}
	if head.page != root {
		t.Fatal("ivBack must still pop the history")
	}
	if st.gen != pre || st.page != other {
		t.Fatal("the replaced head must stay frozen")
	}
	if landed, _ := a.ivLandRelated(7, pre, ivPageJSON("https://telegra.ph/straggler"), nil); landed {
		t.Fatal("a fetch captured before the back must be dropped (R26)")
	}
}
