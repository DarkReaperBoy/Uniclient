package tests

import (
	"fmt"
	"testing"
	"time"

	. "uniclient/ui/app"
	"uniclient/ui/dialogs"
	"uniclient/ui/dialogs/render"
	chatrender "uniclient/ui/history/render"
	"uniclient/ui/material"
)

func filterRowNames(t *testing.T, m Model) []string {
	t.Helper()
	names := make([]string, 0, len(m.Dialogs.Rows))
	for _, r := range m.Dialogs.Rows {
		names = append(names, r.Name)
	}
	return names
}

func eqRowNames(got []string, want ...string) bool {
	if len(got) != len(want) {
		return false
	}
	for i := range got {
		if got[i] != want[i] {
			return false
		}
	}
	return true
}

func typeSearch(t *testing.T, m Model, text string) Model {
	t.Helper()
	m, _ = Update(m, SearchTyped{Text: text, Now: 1000})
	return m
}

func backspaceSearch(t *testing.T, m Model, n int) Model {
	t.Helper()
	for i := 0; i < n; i++ {
		m, _ = Update(m, SearchBackspace{Now: 1000})
	}
	return m
}

func filteredChatsModel(t *testing.T) Model {
	t.Helper()
	nowMs := localMs(2026, time.November, 30, 15, 0)
	alice := snapshotChats(nowMs, "77", "Alice", "hi", 1, "", false, 0, 0, false)
	bob := snapshotChats(nowMs, "88", "Bob", "yo", 1, "", false, 0, 0, false)
	carol := snapshotChats(nowMs, "99", "Carol", "hey", 1, "", false, 0, 0, false)
	return applyEngineEvent(t, feedsModel(t, 1440, 900), chatSnapshotWire("tele_02", alice+","+bob+","+carol, nowMs))
}

func TestSearchFilterNarrowsAndWidens(t *testing.T) {
	m := filteredChatsModel(t)
	if !eqRowNames(filterRowNames(t, m), "Alice", "Bob", "Carol") {
		t.Fatalf("unfiltered rows = %v", filterRowNames(t, m))
	}
	m = typeSearch(t, m, "al")
	if !eqRowNames(filterRowNames(t, m), "Alice") {
		t.Fatalf("filter 'al' rows = %v", filterRowNames(t, m))
	}
	m = typeSearch(t, m, "x")
	if !eqRowNames(filterRowNames(t, m)) {
		t.Fatalf("filter 'alx' rows = %v", filterRowNames(t, m))
	}
	m = backspaceSearch(t, m, 3)
	if !eqRowNames(filterRowNames(t, m), "Alice", "Bob", "Carol") {
		t.Fatalf("cleared filter rows = %v", filterRowNames(t, m))
	}
}

func TestSearchFilterGarbageQueryShowsAll(t *testing.T) {
	m := filteredChatsModel(t)
	m = typeSearch(t, m, "!!! ")
	if !eqRowNames(filterRowNames(t, m), "Alice", "Bob", "Carol") {
		t.Fatalf("garbage query must keep the full list, got %v", filterRowNames(t, m))
	}
}

func TestSearchFilterCaseAccentFolds(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	jose := snapshotChats(nowMs, "77", "José", "hi", 1, "", false, 0, 0, false)
	alice := snapshotChats(nowMs, "88", "Alice", "yo", 1, "", false, 0, 0, false)
	m := applyEngineEvent(t, feedsModel(t, 1440, 900), chatSnapshotWire("tele_02", jose+","+alice, nowMs))
	m = typeSearch(t, m, "ALI")
	if !eqRowNames(filterRowNames(t, m), "Alice") {
		t.Fatalf("uppercase query rows = %v", filterRowNames(t, m))
	}
	m = backspaceSearch(t, m, 3)
	m = typeSearch(t, m, "jos")
	if !eqRowNames(filterRowNames(t, m), "José") {
		t.Fatalf("accent-fold query rows = %v", filterRowNames(t, m))
	}
}

func TestSearchFilterSelectionFollowsAndRestores(t *testing.T) {
	m := filteredChatsModel(t)
	m, _ = Update(m, DialogRowPressed{Index: 0})
	if m.Dialogs.Selected != 0 {
		t.Fatalf("press must select, got %d", m.Dialogs.Selected)
	}
	m = typeSearch(t, m, "al")
	if m.Dialogs.Selected != 0 {
		t.Fatalf("selected row matches filter and must follow, got %d", m.Dialogs.Selected)
	}
	m = typeSearch(t, m, "x")
	if m.Dialogs.Selected != -1 {
		t.Fatalf("selection filtered out must clamp to -1, got %d", m.Dialogs.Selected)
	}
	m, _ = Update(m, SearchFocusLost{})
	if !eqRowNames(filterRowNames(t, m)) {
		t.Fatalf("blur must keep the filter, got %v", filterRowNames(t, m))
	}
	m = backspaceSearch(t, m, 1)
	if m.Dialogs.Selected != 0 {
		t.Fatalf("widen must follow the selected row again, got %d", m.Dialogs.Selected)
	}
	m = backspaceSearch(t, m, 2)
	if m.Dialogs.Selected != 0 {
		t.Fatalf("clear must restore selection by identity, got %d", m.Dialogs.Selected)
	}
}

func TestSearchFilterSelectionGoneWhenChatLeavesData(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	m := filteredChatsModel(t)
	m, _ = Update(m, DialogRowPressed{Index: 0})
	m = typeSearch(t, m, "bo")
	if m.Dialogs.Selected != -1 {
		t.Fatalf("filtered-out selection must clamp, got %d", m.Dialogs.Selected)
	}
	bob := snapshotChats(nowMs, "88", "Bob", "yo", 1, "", false, 0, 0, false)
	m = applyEngineEvent(t, m, chatSnapshotWire("tele_02", bob, nowMs))
	m = backspaceSearch(t, m, 2)
	if m.Dialogs.Selected != -1 {
		t.Fatalf("chat gone from data must clear selection, got %d", m.Dialogs.Selected)
	}
}

func TestSearchFilterScrollClamps(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	chats := ""
	for i := 0; i < 60; i++ {
		if i > 0 {
			chats += ","
		}
		chats += snapshotChats(nowMs, fmt.Sprintf("c%02d", i), fmt.Sprintf("chat%02d", i), "m", 1, "", false, 0, 0, false)
	}
	m := applyEngineEvent(t, feedsModel(t, 1440, 900), chatSnapshotWire("tele_02", chats, nowMs))
	m, _ = Update(m, DialogsScrolled{DeltaY: 100000})
	if m.DialogsScroll.Top <= 0 {
		t.Fatalf("scrolled Top = %d, want deep", m.DialogsScroll.Top)
	}
	m = typeSearch(t, m, "chat")
	maxTop := m.Dialogs.MaxOffset(m.Columns().Dialogs, m.DialogsScroll.Height)
	if m.DialogsScroll.Top > maxTop {
		t.Fatalf("filter shrink must clamp scroll, Top = %d > max %d", m.DialogsScroll.Top, maxTop)
	}
	if m.DialogsToUp.Shown && maxTop == 0 {
		t.Fatalf("to-up must hide when the filtered list fits the viewport")
	}
	m = backspaceSearch(t, m, 4)
	if m.DialogsScroll.Top > m.Dialogs.MaxOffset(m.Columns().Dialogs, m.DialogsScroll.Height) {
		t.Fatalf("widen must keep scroll clamped, Top = %d", m.DialogsScroll.Top)
	}
}

func TestSearchFilterOpenJourney(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	alice := snapshotChats(nowMs, "77", "Alice", "hi", 1, "", false, 0, 0, false)
	bob := snapshotChats(nowMs, "88", "Bob", "yo", 1, "", false, 0, 0, false)
	port := &fakeChatPort{ok: true, msgs: []WireMessage{
		{ID: "m1", SenderID: "u2", SenderName: "Bob", Text: "hi", TimestampMs: nowMs - 60000, Status: 2},
	}}
	m := applyEngineEvent(t, feedsModel(t, 1440, 900).WithPort(port), chatSnapshotWire("tele_02", alice+","+bob, nowMs))
	m = typeSearch(t, m, "bo")
	if len(m.Dialogs.Rows) != 1 || m.Dialogs.Rows[0].Name != "Bob" {
		t.Fatalf("filter rows = %v", filterRowNames(t, m))
	}
	next, cmd := Update(m, DialogsPressed{X: 20, Y: 10, Now: 2})
	if cmd == nil {
		t.Fatal("filtered row press must produce an open cmd")
	}
	if next.Open != (ChatRef{Account: "tele_02", ID: "88"}) {
		t.Fatalf("open ref = %+v, want Bob's chat", next.Open)
	}
	loaded, ok := cmd().(ChatLoaded)
	if !ok {
		t.Fatal("open cmd must produce ChatLoaded")
	}
	if port.chat != "88" {
		t.Fatalf("port chat = %q, want 88", port.chat)
	}
	next, _ = Update(next, loaded)
	if len(next.Chat.Items) != 1 {
		t.Fatalf("items = %d, want 1", len(next.Chat.Items))
	}
}

func TestSearchFilterDialogsLoadedPath(t *testing.T) {
	m := InitialModel()
	m, _ = Update(m, DialogsLoaded{Rows: []dialogs.Entry{{Name: "alpha"}, {Name: "beta"}, {Name: "gamma"}}})
	m = typeSearch(t, m, "a")
	if !eqRowNames(filterRowNames(t, m), "alpha") {
		t.Fatalf("feed rows filter = %v", filterRowNames(t, m))
	}
	m = backspaceSearch(t, m, 1)
	if !eqRowNames(filterRowNames(t, m), "alpha", "beta", "gamma") {
		t.Fatalf("feed rows restore = %v", filterRowNames(t, m))
	}
}

func TestSearchFilterDialogsLoadedSelectionHonest(t *testing.T) {
	m := InitialModel()
	m, _ = Update(m, DialogsLoaded{Rows: []dialogs.Entry{{Name: "alpha"}, {Name: "beta"}}})
	m, _ = Update(m, DialogRowPressed{Index: 1})
	m = typeSearch(t, m, "alp")
	if m.Dialogs.Selected != -1 {
		t.Fatalf("identityless filtered-out selection must drop, got %d", m.Dialogs.Selected)
	}
	m = backspaceSearch(t, m, 3)
	if m.Dialogs.Selected != -1 {
		t.Fatalf("identityless selection cannot restore, got %d", m.Dialogs.Selected)
	}
}

func TestSearchFilterSnapshotKeepsFilterActive(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	m := filteredChatsModel(t)
	m = typeSearch(t, m, "bo")
	alice := snapshotChats(nowMs, "77", "Alice", "hi", 1, "", false, 0, 0, false)
	bob := snapshotChats(nowMs, "88", "Bob", "yo", 1, "", false, 0, 0, false)
	carol := snapshotChats(nowMs, "99", "Carol", "hey", 1, "", false, 0, 0, false)
	m = applyEngineEvent(t, m, chatSnapshotWire("tele_02", alice+","+bob+","+carol, nowMs))
	if !eqRowNames(filterRowNames(t, m), "Bob") {
		t.Fatalf("snapshot must re-apply the active filter, got %v", filterRowNames(t, m))
	}
}

func TestSearchFilterEmptyResultHonestPane(t *testing.T) {
	m := filteredChatsModel(t)
	m = typeSearch(t, m, "zz")
	if !eqRowNames(filterRowNames(t, m)) {
		t.Fatalf("no-match rows = %v", filterRowNames(t, m))
	}
	scene := View(m)
	if len(scene.Dialogs.Rows) != 0 {
		t.Fatalf("scene rows = %d, want 0", len(scene.Dialogs.Rows))
	}
	if scene.Dialogs.EmptyText == AddAccountPrompt {
		t.Fatal("accounts exist: no-match filter must not paint the add-account prompt")
	}
}

func TestSearchFilterPaintSmoke(t *testing.T) {
	p := render.NewPainter()
	cp := chatrender.NewChatPainter()
	gtx := renderContext()
	sch := material.SchemeFor(material.Light)
	m := filteredChatsModel(t)
	m = typeSearch(t, m, "al")
	scene := View(m)
	p.PaintPane(gtx, scene.Dialogs, sch)
	cp.PaintChatPane(gtx, scene.Chat, sch)
	narrow := InitialModel()
	narrow, _ = Update(narrow, Resized{Width: 390, Height: 844})
	narrow = typeSearch(t, narrow, "al")
	p.PaintPane(gtx, View(narrow).Dialogs, sch)
}
