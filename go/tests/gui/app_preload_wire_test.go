package tests

import (
	"fmt"
	"testing"
	"time"

	. "uniclient/ui/app"
	"uniclient/ui/dialogs"
)

type pagedPort struct {
	msgs        []WireMessage
	newestLimit int
	beforePages [][]WireMessage
	beforeCalls []int64
}

func (p *pagedPort) Messages(accountID, chatID string, limit int) ([]WireMessage, bool) {
	p.newestLimit = limit
	if len(p.msgs) <= limit {
		return p.msgs, true
	}
	return p.msgs[len(p.msgs)-limit:], true
}

func (p *pagedPort) MessagesBefore(accountID, chatID string, beforeMs int64, limit int) ([]WireMessage, bool) {
	p.beforeCalls = append(p.beforeCalls, beforeMs)
	if len(p.beforePages) == 0 {
		return nil, true
	}
	page := p.beforePages[0]
	p.beforePages = p.beforePages[1:]
	return page, true
}

func (p *pagedPort) Send(accountID, chatID, text string) bool {
	return true
}

func (p *pagedPort) SearchGlobalChats(accountID, query string) ([]dialogs.Entry, bool) {
	return nil, true
}

func preloadMsgs(n int, baseMs int64) []WireMessage {
	msgs := make([]WireMessage, n)
	for i := range msgs {
		msgs[i] = WireMessage{
			ID:          fmt.Sprintf("m%03d", i+1),
			SenderID:    "u1",
			SenderName:  "Alice",
			Text:        "msg",
			TimestampMs: baseMs + int64(i)*60000,
			Status:      2,
		}
	}
	return msgs
}

func numericMsgs(n int, baseMs int64) []WireMessage {
	msgs := preloadMsgs(n, baseMs)
	for i := range msgs {
		msgs[i].ID = fmt.Sprintf("%d", i+1)
	}
	return msgs
}

func openPreloadChat(t *testing.T, port *pagedPort, msgs []WireMessage, rowWire string) Model {
	t.Helper()
	nowMs := localMs(2026, time.November, 30, 15, 0)
	port.msgs = msgs
	m := applyEngineEvent(t, feedsModel(t, 1440, 900).WithPort(port), chatSnapshotWire("tele_02", rowWire, nowMs))
	m, cmd := Update(m, DialogsPressed{X: 20, Y: 10, Now: 1})
	if cmd == nil {
		t.Fatal("press must open")
	}
	m, _ = Update(m, cmd())
	return m
}

func plainRowWire(nowMs int64) string {
	return snapshotChats(nowMs, "77", "Alice", "hi", 1, "", false, 0, 0, false)
}

func TestOpenChatCarriesMoreAboveCursor(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	port := &pagedPort{}
	m := openPreloadChat(t, port, preloadMsgs(60, localMs(2026, time.November, 30, 10, 0)), plainRowWire(nowMs))
	if !m.ChatMoreAbove {
		t.Fatal("a full newest page must carry more-above")
	}
	if len(m.Chat.Items) != 50 {
		t.Fatalf("items = %d, want the newest 50", len(m.Chat.Items))
	}
	full := &pagedPort{}
	m = openPreloadChat(t, full, preloadMsgs(30, localMs(2026, time.November, 30, 10, 0)), plainRowWire(nowMs))
	if m.ChatMoreAbove {
		t.Fatal("a short newest page must not carry more-above")
	}
}

func TestChatPreloadTopFetchesOlderPage(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	base := localMs(2026, time.November, 30, 10, 0)
	all := preloadMsgs(60, base)
	port := &pagedPort{beforePages: [][]WireMessage{all[:10]}}
	m := openPreloadChat(t, port, all[10:], plainRowWire(nowMs))
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(50, 50)})
	m, cmd := Update(m, ChatPreloadTopRequested{})
	if cmd == nil {
		t.Fatal("the preload request must fetch the older page when more-above is armed")
	}
	if len(port.beforeCalls) != 0 {
		t.Fatal("the fetch happens in the cmd, not at request time")
	}
	msg := cmd()
	prepended, ok := msg.(ChatPrepended)
	if !ok {
		t.Fatalf("preload cmd produced %T, want ChatPrepended", msg)
	}
	if len(prepended.Msgs) != 10 {
		t.Fatalf("prepended msgs = %d, want 10", len(prepended.Msgs))
	}
	if prepended.MoreAbove {
		t.Fatal("a short older page must close the cursor")
	}
	if len(port.beforeCalls) != 1 {
		t.Fatalf("before calls = %d, want 1", len(port.beforeCalls))
	}
	wantBefore := all[10].TimestampMs + 1
	if port.beforeCalls[0] != wantBefore {
		t.Fatalf("before cursor = %d, want %d (oldest loaded ts + 1)", port.beforeCalls[0], wantBefore)
	}
	m, _ = Update(m, prepended)
	if len(m.Chat.Items) != 60 {
		t.Fatalf("items after prepend = %d, want 60", len(m.Chat.Items))
	}
	if m.Chat.Items[0].Text != "msg" || m.Chat.Items[0].DateText == "" {
		t.Fatalf("the prepended page must derive its own items: %+v", m.Chat.Items[0])
	}
	m, cmd = Update(m, ChatMeasured{Heights: uniformHeights(60, 50)})
	if cmd != nil {
		t.Fatal("cursor closed: no further preload")
	}
}

func TestChatPreloadTopKeepsFullPageCursor(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	base := localMs(2026, time.November, 30, 10, 0)
	all := preloadMsgs(120, base)
	port := &pagedPort{beforePages: [][]WireMessage{all[20:70]}}
	m := openPreloadChat(t, port, all[70:], plainRowWire(nowMs))
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(50, 50)})
	m, cmd := Update(m, ChatPreloadTopRequested{})
	prepended, ok := cmd().(ChatPrepended)
	if !ok {
		t.Fatalf("cmd produced %T, want ChatPrepended", cmd())
	}
	if !prepended.MoreAbove {
		t.Fatal("a full older page must keep the cursor open")
	}
}

func TestChatPreloadDedupsBoundaryMessage(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	base := localMs(2026, time.November, 30, 10, 0)
	all := preloadMsgs(60, base)
	older := append(append([]WireMessage(nil), all[5:10]...), all[10])
	port := &pagedPort{beforePages: [][]WireMessage{older}}
	m := openPreloadChat(t, port, all[10:], plainRowWire(nowMs))
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(50, 50)})
	m, cmd := Update(m, ChatPreloadTopRequested{})
	prepended, ok := cmd().(ChatPrepended)
	if !ok {
		t.Fatalf("cmd produced %T, want ChatPrepended", cmd())
	}
	for _, wm := range prepended.Msgs {
		if wm.ID == all[10].ID {
			t.Fatalf("the already-loaded boundary message must be deduped, got %s", wm.ID)
		}
	}
	if len(prepended.Msgs) != 5 {
		t.Fatalf("deduped page = %d, want 5", len(prepended.Msgs))
	}
}

func TestChatPreloadTerminatesOnEmptyProgress(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	base := localMs(2026, time.November, 30, 10, 0)
	all := preloadMsgs(110, base)
	port := &pagedPort{beforePages: [][]WireMessage{all[10:60]}}
	m := openPreloadChat(t, port, all[60:], plainRowWire(nowMs))
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(50, 50)})
	m, cmd := Update(m, ChatPreloadTopRequested{})
	prepended := cmd().(ChatPrepended)
	if len(prepended.Msgs) != 50 || !prepended.MoreAbove {
		t.Fatalf("setup: a full fresh page must keep the cursor, got (%d, %v)", len(prepended.Msgs), prepended.MoreAbove)
	}
	port.beforePages = [][]WireMessage{all[10:60]}
	m, _ = Update(m, prepended)
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(100, 50)})
	m, cmd = Update(m, ChatPreloadTopRequested{})
	prepended2 := cmd().(ChatPrepended)
	if len(prepended2.Msgs) != 0 {
		t.Fatalf("an all-duplicate page must dedupe to zero, got %d", len(prepended2.Msgs))
	}
	if prepended2.MoreAbove {
		t.Fatal("a no-progress page must close the cursor (loop breaker)")
	}
}

func TestChatPreloadTopGatesOnCursorState(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	base := localMs(2026, time.November, 30, 10, 0)
	all := preloadMsgs(60, base)
	port := &pagedPort{}
	m := openPreloadChat(t, port, all[:30], plainRowWire(nowMs))
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(30, 50)})
	if _, cmd := Update(m, ChatPreloadTopRequested{}); cmd != nil {
		t.Fatal("no more-above must never fetch")
	}
	m2, _ := Update(InitialModel(), ChatLoaded{Msgs: all, Items: preloadItems(60)})
	m2, _ = Update(m2, ChatMeasured{Heights: uniformHeights(60, 50)})
	if _, cmd := Update(m2, ChatPreloadTopRequested{}); cmd != nil {
		t.Fatal("no port must never fetch")
	}
}

func TestChatPreloadBarMovesToOlderFirstUnread(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	base := localMs(2026, time.November, 30, 10, 0)
	all := numericMsgs(60, base)
	port := &pagedPort{beforePages: [][]WireMessage{all[:10]}}
	m := openPreloadChat(t, port, all[10:], unreadRowWire(nowMs, 5))
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(50, 50)})
	barsBefore := 0
	for _, it := range m.Chat.Items {
		if it.UnreadBar != "" {
			barsBefore++
		}
	}
	if barsBefore != 1 {
		t.Fatalf("setup: exactly one bar before the prepend, got %d", barsBefore)
	}
	m, cmd := Update(m, ChatPreloadTopRequested{})
	prepended, ok := cmd().(ChatPrepended)
	if !ok {
		t.Fatalf("cmd produced %T, want ChatPrepended", cmd())
	}
	m, _ = Update(m, prepended)
	bars := 0
	barAt := -1
	for i, it := range m.Chat.Items {
		if it.UnreadBar != "" {
			bars++
			barAt = i
		}
	}
	if bars != 1 {
		t.Fatalf("one bar total after the prepend, got %d", bars)
	}
	if barAt != 5 {
		t.Fatalf("the bar must move to the older page's first unread (item 5, id 6), got %d", barAt)
	}
}
