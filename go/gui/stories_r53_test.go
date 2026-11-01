package gui

import (
	"errors"
	"sync"
	"testing"

	"uniclient/engine"
)

func storyTestHead(a *App, sv *storyViewerState) int {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.storyView = sv
	a.storyViewGen++
	return a.storyViewGen
}

func storyCurrentHead(a *App) *storyViewerState {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.storyView
}

func TestUpdateStoryViewContract(t *testing.T) {
	a := &App{}
	if a.updateStoryView(func(sv *storyViewerState) bool { sv.loading = true; return true }) {
		t.Fatalf("nil head: installer reports an install")
	}
	gen := storyTestHead(a, &storyViewerState{accountID: "acc", chatID: "chat", loading: true})
	frozen := storyCurrentHead(a)

	if a.updateStoryView(func(sv *storyViewerState) bool { return false }) {
		t.Fatalf("abort: installer reports an install")
	}
	if storyCurrentHead(a) != frozen {
		t.Fatalf("abort: head replaced anyway")
	}

	if !a.updateStoryView(func(sv *storyViewerState) bool { sv.cur = 3; return true }) {
		t.Fatalf("install: installer reports no install")
	}
	live := storyCurrentHead(a)
	if live == frozen || live.cur != 3 || frozen.cur != 0 {
		t.Fatalf("install: cur=%d frozen.cur=%d fresh=%v", live.cur, frozen.cur, live == frozen)
	}

	a.mu.Lock()
	g := a.storyViewGen
	a.mu.Unlock()
	if g != gen {
		t.Fatalf("installer bumped the gen: %d != %d", g, gen)
	}

	var wg sync.WaitGroup
	for w := 0; w < 4; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := 0; i < 250; i++ {
				a.updateStoryView(func(sv *storyViewerState) bool {
					sv.cur = i
					sv.loading = i%2 == 0
					return true
				})
			}
		}()
	}
	wg.Wait()
	if frozen.cur != 0 || !frozen.loading || frozen.err != "" || len(frozen.items) != 0 {
		t.Fatalf("frozen head mutated by hammer: %+v", *frozen)
	}
	if storyCurrentHead(a) == nil {
		t.Fatalf("hammer lost the head")
	}
}

func TestStoryViewerSnapshotImmutableUnderTails(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	a.mu.Lock()
	a.storyView = &storyViewerState{accountID: "acc", chatID: "chat", loading: true}
	a.storyViewGen++
	gen := a.storyViewGen
	frozen := a.storyView
	a.mu.Unlock()

	stop := make(chan struct{})
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		for {
			select {
			case <-stop:
				return
			default:
				_ = frozen.loading
				_ = frozen.err
				_ = len(frozen.items)
				_ = frozen.cur
				_ = len(frozen.items[0:0])
			}
		}
	}()
	for i := 0; i < 300; i++ {
		a.storyFetchDone(gen, "acc", "chat", `[{"id":1}]`, nil)
	}
	close(stop)
	wg.Wait()

	a.mu.Lock()
	defer a.mu.Unlock()
	if frozen.cur != 0 || len(frozen.items) != 0 || frozen.err != "" || !frozen.loading {
		t.Fatalf("frozen head mutated: cur=%d items=%d err=%q loading=%v",
			frozen.cur, len(frozen.items), frozen.err, frozen.loading)
	}
}

func TestStoryFetchTailSessionGuarded(t *testing.T) {
	a := &App{eng: &engine.Engine{}}

	a.openStoryViewer(engine.ChatInfo{AccountID: "acc", ChatID: "chat", Title: "T", StoryCount: 1})
	a.mu.Lock()
	g1, h1 := a.storyViewGen, a.storyView
	a.mu.Unlock()
	if h1 == nil || h1.accountID != "acc" || h1.chatID != "chat" {
		t.Fatalf("open head wrong: %+v", h1)
	}
	a.openStoryViewer(engine.ChatInfo{AccountID: "acc", ChatID: "chat", Title: "T", StoryCount: 1})
	a.mu.Lock()
	g2, h2 := a.storyViewGen, a.storyView
	a.mu.Unlock()
	if g2 <= g1 || h2 == h1 {
		t.Fatalf("reopen did not bump/replace: g2=%d g1=%d same=%v", g2, g1, h2 == h1)
	}

	g3 := storyTestHead(a, &storyViewerState{accountID: "acc", chatID: "chat", loading: true})
	h3 := storyCurrentHead(a)

	a.storyFetchDone(g1, "acc", "chat", `[{"id":1}]`, nil)
	a.storyFetchDone(g2, "acc", "chat", `[{"id":1}]`, nil)
	a.storyFetchDone(g3, "acc", "other", `[{"id":1}]`, nil)
	a.storyFetchDone(g3, "other", "chat", `[{"id":1}]`, nil)
	if storyCurrentHead(a) != h3 || !h3.loading || len(h3.items) != 0 || h3.err != "" {
		t.Fatalf("stale/foreign tail touched the head: %+v", *storyCurrentHead(a))
	}

	a.storyFetchDone(g3, "acc", "chat", `[{"id":1,"caption":"c"},{"id":2}]`, nil)
	live := storyCurrentHead(a)
	if live == h3 || live.loading || len(live.items) != 2 || live.items[1].ID != 2 || live.err != "" {
		t.Fatalf("live tail did not install: %+v", *live)
	}

	a.storyFetchDone(g3, "acc", "chat", "{not json", nil)
	if live = storyCurrentHead(a); live.err == "" || len(live.items) != 2 {
		t.Fatalf("bad JSON: err=%q items=%d", live.err, len(live.items))
	}
	a.storyFetchDone(g3, "acc", "chat", "", errors.New("boom"))
	if live = storyCurrentHead(a); live.err != "boom" {
		t.Fatalf("engine error not surfaced: %q", live.err)
	}

	a.closeStoryViewer()
	if storyCurrentHead(a) != nil {
		t.Fatalf("close left a head")
	}
	a.storyFetchDone(g3, "acc", "chat", `[{"id":1}]`, nil)
	if storyCurrentHead(a) != nil {
		t.Fatalf("tail resurrected a closed viewer")
	}
}

func TestStoryReactFlipContract(t *testing.T) {
	a := &App{}
	storyTestHead(a, &storyViewerState{
		accountID: "acc", chatID: "chat",
		items: []storyItem{{ID: 1}, {ID: 2, SentReaction: "❤️"}},
	})
	frozen := storyCurrentHead(a)

	if !a.flipStoryReaction("acc", "chat", 1, "", "👍") {
		t.Fatalf("optimistic flip aborted")
	}
	live := storyCurrentHead(a)
	if live == frozen || live.items[0].SentReaction != "👍" || live.items[1].SentReaction != "❤️" {
		t.Fatalf("flip wrong: %+v", live.items)
	}
	if frozen.items[0].SentReaction != "" {
		t.Fatalf("deep copy violated: frozen items mutated")
	}

	if a.flipStoryReaction("acc", "chat", 1, "❤️", "") {
		t.Fatalf("mismatched flip applied")
	}
	if storyCurrentHead(a).items[0].SentReaction != "👍" {
		t.Fatalf("mismatched flip stomped the newer reaction")
	}

	if a.flipStoryReaction("acc", "chat", 99, "", "x") {
		t.Fatalf("unknown story flipped")
	}
	if a.flipStoryReaction("other", "chat", 1, "👍", "") {
		t.Fatalf("foreign account flipped")
	}
	if a.flipStoryReaction("acc", "other", 1, "👍", "") {
		t.Fatalf("foreign chat flipped")
	}
	a.closeStoryViewer()
	if a.flipStoryReaction("acc", "chat", 1, "👍", "") {
		t.Fatalf("closed viewer flipped")
	}
}

func TestStoryReactRevertTailGuarded(t *testing.T) {
	a := &App{}
	storyTestHead(a, &storyViewerState{accountID: "acc", chatID: "chat", items: []storyItem{{ID: 1, SentReaction: "👍"}}})

	a.storyReactDone("acc", "chat", 1, "👍", errors.New("boom"))
	if live := storyCurrentHead(a); live.items[0].SentReaction != "" {
		t.Fatalf("failed react not reverted: %q", live.items[0].SentReaction)
	}
	a.mu.Lock()
	toast := a.toast
	a.mu.Unlock()
	if toast != "React: boom" {
		t.Fatalf("no honest toast: %q", toast)
	}

	storyTestHead(a, &storyViewerState{accountID: "acc", chatID: "chat", items: []storyItem{{ID: 1, SentReaction: "❤️"}}})
	a.storyReactDone("acc", "chat", 1, "👍", errors.New("boom2"))
	if live := storyCurrentHead(a); live.items[0].SentReaction != "❤️" {
		t.Fatalf("newer reaction stomped: %q", live.items[0].SentReaction)
	}

	a.mu.Lock()
	a.toast = ""
	a.mu.Unlock()
	storyTestHead(a, &storyViewerState{accountID: "acc", chatID: "chat", items: []storyItem{{ID: 1, SentReaction: "🎉"}}})
	a.storyReactDone("acc", "chat", 1, "🎉", nil)
	if live := storyCurrentHead(a); live.items[0].SentReaction != "🎉" {
		t.Fatalf("success path mutated state: %q", live.items[0].SentReaction)
	}
	a.mu.Lock()
	toast = a.toast
	a.mu.Unlock()
	if toast != "" {
		t.Fatalf("success path toasted: %q", toast)
	}

	a.closeStoryViewer()
	a.storyReactDone("acc", "chat", 1, "🎉", errors.New("boom3"))
	if storyCurrentHead(a) != nil {
		t.Fatalf("revert tail resurrected a closed viewer")
	}
}

func TestStoryAdvanceInstallsFreshHead(t *testing.T) {
	a := &App{}
	storyTestHead(a, &storyViewerState{accountID: "acc", chatID: "chat", items: []storyItem{{ID: 1}, {ID: 2}, {ID: 3}}})
	frozen := storyCurrentHead(a)

	a.storyAdvance(1)
	live := storyCurrentHead(a)
	if live == frozen || live.cur != 1 || frozen.cur != 0 {
		t.Fatalf("advance: cur=%d frozen.cur=%d fresh=%v", live.cur, frozen.cur, live == frozen)
	}

	a.storyAdvance(-5)
	if live = storyCurrentHead(a); live.cur != 0 {
		t.Fatalf("clamp-left: cur=%d", live.cur)
	}

	a.storyAdvance(5)
	if storyCurrentHead(a) != nil {
		t.Fatalf("past-end did not close")
	}

	a.storyAdvance(1)
	if storyCurrentHead(a) != nil {
		t.Fatalf("closed viewer resurrected")
	}
}

func TestStoryReplyDraftLifecycle(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	storyTestHead(a, &storyViewerState{accountID: "acc", chatID: "chat", items: []storyItem{{ID: 1}}})
	if !a.updateStoryView(func(sv *storyViewerState) bool { sv.replyOn = true; return true }) {
		t.Fatalf("arm reply failed")
	}
	a.wid.storyReplyEd.SetText("half-written")
	if a.wid.storyReplyEd.Text() != "half-written" {
		t.Fatalf("editor setup failed")
	}

	a.storyAdvance(9)
	if storyCurrentHead(a) != nil {
		t.Fatalf("viewer not closed")
	}
	if txt := a.wid.storyReplyEd.Text(); txt != "" {
		t.Fatalf("draft leaked across close: %q", txt)
	}

	storyTestHead(a, &storyViewerState{accountID: "acc", chatID: "chat", items: []storyItem{{ID: 1}}})
	a.wid.storyReplyEd.SetText("again")
	a.closeStoryViewer()
	if txt := a.wid.storyReplyEd.Text(); txt != "" {
		t.Fatalf("draft leaked across direct close: %q", txt)
	}
	a.openStoryViewer(engine.ChatInfo{AccountID: "acc", ChatID: "chat", StoryCount: 1})
	live := storyCurrentHead(a)
	if live == nil || live.replyOn || live.reactOpen {
		t.Fatalf("fresh open carries viewer flags: %+v", live)
	}
}
