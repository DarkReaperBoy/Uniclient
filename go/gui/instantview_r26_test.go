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

// TestIVLandRelatedStaleGeneration pins R26: a related-article fetch
// captures the reader state's pointer AND generation; backing out
// (ivBack) or navigating again bumps the generation, so a straggler fetch
// landing late must be dropped whole — it may never push itself (or a
// wrong page) onto the history. Pre-fix, the only guard was
// `!cur.loading`: back-during-fetch rearmed the flag on the NEXT
// navigation and the straggler sailed through, corrupting the back stack
// (user backs from C and lands on a page they never opened).
func TestIVLandRelatedStaleGeneration(t *testing.T) {
	a := &App{}
	root := &ivPage{URL: "https://telegra.ph/root", Blocks: []ivBlock{{Type: "paragraph"}}}
	st := &ivState{accountID: "acc", url: root.URL, page: root, gen: 5}
	a.mu.Lock()
	a.iv = st
	a.mu.Unlock()

	// Current-generation fetch lands: new page shown, old one pushed.
	landed, fb := a.ivLandRelated(st, 5, ivPageJSON("https://telegra.ph/b"), nil)
	if !landed || fb {
		t.Fatalf("current-generation fetch must land (landed=%v fallback=%v)", landed, fb)
	}
	if st.page.URL != "https://telegra.ph/b" || len(st.hist) != 1 || st.hist[0] != root {
		t.Fatalf("landing must push the old page and show the new one: url=%s hist=%d", st.page.URL, len(st.hist))
	}

	// Stale generation (user navigated again mid-flight): dropped whole.
	st.gen = 6
	if landed, _ := a.ivLandRelated(st, 5, ivPageJSON("https://telegra.ph/c"), nil); landed {
		t.Fatal("stale-generation fetch must be dropped (R26)")
	}
	if st.page.URL != "https://telegra.ph/b" || len(st.hist) != 1 {
		t.Fatal("a stale fetch must not touch the history")
	}

	// Replaced state (overlay closed / reopened elsewhere): dropped whole.
	a.mu.Lock()
	a.iv = nil
	a.mu.Unlock()
	if landed, _ := a.ivLandRelated(st, 6, ivPageJSON("https://telegra.ph/c"), nil); landed {
		t.Fatal("fetch against a replaced state must be dropped")
	}

	// Current-generation error lands as the reader's error state (toast path).
	a.mu.Lock()
	a.iv = st
	a.mu.Unlock()
	landed, fb = a.ivLandRelated(st, 6, nil, errors.New("boom"))
	if !landed || fb {
		t.Fatalf("current-generation error must land (landed=%v fallback=%v)", landed, fb)
	}
	if st.loading || st.err != "boom" {
		t.Fatalf("error landing must clear loading and set err: loading=%v err=%q", st.loading, st.err)
	}

	// Current-generation unparseable payload lands with the browser fallback.
	landed, fb = a.ivLandRelated(st, 6, []byte("not-json"), nil)
	if !landed || !fb {
		t.Fatalf("unparseable page at the current generation must land with the browser fallback (landed=%v fallback=%v)", landed, fb)
	}
}

// TestIVBackBumpsGeneration pins the other half of R26's wiring: ivBack
// bumps the state's generation (it does not replace the pointer when it
// pops), so a related fetch still in flight when the user went back must
// fail the landing gate.
func TestIVBackBumpsGeneration(t *testing.T) {
	a := &App{}
	root := &ivPage{URL: "https://telegra.ph/root", Blocks: []ivBlock{{Type: "paragraph"}}}
	other := &ivPage{URL: "https://telegra.ph/other", Blocks: []ivBlock{{Type: "paragraph"}}}
	st := &ivState{accountID: "acc", url: other.URL, page: other, hist: []*ivPage{root}, gen: 3}
	a.mu.Lock()
	a.iv = st
	a.mu.Unlock()

	pre := st.gen
	a.ivBack() // pops to root, stays open
	if st.gen <= pre {
		t.Fatalf("ivBack must bump the generation (pre=%d post=%d)", pre, st.gen)
	}
	if st.page != root {
		t.Fatal("ivBack must still pop the history")
	}
	if landed, _ := a.ivLandRelated(st, pre, ivPageJSON("https://telegra.ph/straggler"), nil); landed {
		t.Fatal("a fetch captured before the back must be dropped (R26)")
	}
}
