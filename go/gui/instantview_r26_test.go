package gui

import (
	"encoding/json"
	"errors"
	"testing"
)

func ivPageJSON(u string) []byte {
	raw, _ := json.Marshal(map[string]interface{}{
		"url":    u,
		"title":  u,
		"blocks": []interface{}{plainRT("body")},
	})
	return raw
}

func ivHead(a *App) *ivState {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.iv
}

func TestIVLandRelatedStaleGeneration(t *testing.T) {
	a := &App{}
	root := &ivPage{URL: "https://telegra.ph/root", Blocks: []ivBlock{{Type: "paragraph"}}}
	st := &ivState{accountID: "acc", url: root.URL, page: root, gen: 5, openID: 7}
	a.mu.Lock()
	a.iv = st
	a.mu.Unlock()

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
	if st.page != root || len(st.hist) != 0 {
		t.Fatal("the replaced head must stay frozen")
	}

	a.updateIV(func(cur *ivState) bool { cur.gen = 6; return true })
	if landed, _ := a.ivLandRelated(7, 5, ivPageJSON("https://telegra.ph/c"), nil); landed {
		t.Fatal("stale-generation fetch must be dropped (R26)")
	}
	head = ivHead(a)
	if head.page.URL != "https://telegra.ph/b" || len(head.hist) != 1 {
		t.Fatal("a stale fetch must not touch the history")
	}

	a.mu.Lock()
	a.iv = nil
	a.mu.Unlock()
	if landed, _ := a.ivLandRelated(7, 6, ivPageJSON("https://telegra.ph/c"), nil); landed {
		t.Fatal("fetch against a closed reader must be dropped")
	}

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

	landed, fb = a.ivLandRelated(7, 6, []byte("not-json"), nil)
	if !landed || !fb {
		t.Fatalf("unparseable page at the current generation must land with the browser fallback (landed=%v fallback=%v)", landed, fb)
	}

	if landed, _ := a.ivLandRelated(9, 6, ivPageJSON("https://telegra.ph/d"), nil); landed {
		t.Fatal("a foreign-session fetch must be dropped (R46 openID guard)")
	}
}

func TestIVBackBumpsGeneration(t *testing.T) {
	a := &App{}
	root := &ivPage{URL: "https://telegra.ph/root", Blocks: []ivBlock{{Type: "paragraph"}}}
	other := &ivPage{URL: "https://telegra.ph/other", Blocks: []ivBlock{{Type: "paragraph"}}}
	st := &ivState{accountID: "acc", url: other.URL, page: other, hist: []*ivPage{root}, gen: 3, openID: 7}
	a.mu.Lock()
	a.iv = st
	a.mu.Unlock()

	pre := st.gen
	a.ivBack()
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
