package tests

import (
	"strconv"
	"strings"
	"testing"
	"time"

	. "uniclient/ui/app"
	chatrender "uniclient/ui/history/render"
	"uniclient/ui/material"
)

func badgeRowWire(nowMs int64, readInbox, unread int) string {
	return strings.Replace(unreadRowWire(nowMs, readInbox),
		`"unread_count":2`, `"unread_count":`+strconv.Itoa(unread), 1)
}

func downBadgeModel(t *testing.T, readInbox, unread int, msgs []WireMessage) Model {
	t.Helper()
	nowMs := localMs(2026, time.November, 30, 15, 0)
	port := &fakeChatPort{ok: true, msgs: msgs}
	m := applyEngineEvent(t, feedsModel(t, 1440, 900).WithPort(port),
		chatSnapshotWire("tele_02", badgeRowWire(nowMs, readInbox, unread), nowMs))
	m, cmd := Update(m, DialogsPressed{X: 20, Y: 10, Now: 1})
	if cmd == nil {
		t.Fatal("press must open")
	}
	m, _ = Update(m, cmd())
	return m
}

func TestDownBadgeCarriesOpenChatUnreadCount(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	m := downBadgeModel(t, 4, 7, unreadBarMsgs(nowMs))
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(4, 50)})
	scene := View(m)
	if scene.Chat.DownBadgeText != "7" {
		t.Fatalf("pane badge = %q, want 7", scene.Chat.DownBadgeText)
	}
	m, _ = Update(m, ChatScrolled{DeltaY: -100, Now: 2000})
	scene = View(m)
	if scene.Chat.DownBadgeText != "7" {
		t.Fatalf("badge must persist while scrolled: %q", scene.Chat.DownBadgeText)
	}
}

func TestDownBadgeEmptyWithoutUnread(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	m := downBadgeModel(t, 6, 0, unreadBarMsgs(nowMs))
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(4, 50)})
	if s := View(m).Chat.DownBadgeText; s != "" {
		t.Fatalf("zero unread must carry no badge text, got %q", s)
	}
}

func TestDownBadgeClearsOnReadAdvance(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	m := downBadgeModel(t, 4, 5, unreadBarMsgs(nowMs))
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(4, 50)})
	if s := View(m).Chat.DownBadgeText; s != "5" {
		t.Fatalf("setup: badge = %q, want 5", s)
	}
	readAll := strings.Replace(chatUpdatedReadWire(nowMs, 6),
		`"unread_count":2`, `"unread_count":0`, 1)
	m = applyEngineEvent(t, m, readAll)
	if s := View(m).Chat.DownBadgeText; s != "" {
		t.Fatalf("a read advance must clear the badge, got %q", s)
	}
}

func TestDownBadgePaintsWithTheButton(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	msgs := make([]WireMessage, 40)
	for i := range msgs {
		msgs[i] = WireMessage{ID: strconv.Itoa(i + 1), SenderID: "u1", SenderName: "Alice",
			Text: "m", TimestampMs: nowMs - int64(40-i)*60000, Status: 2}
	}
	m := downBadgeModel(t, 20, 9, msgs)
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(40, 50)})
	m, _ = Update(m, ChatScrolled{DeltaY: -500, Now: 2000})
	m, _ = Update(m, ChatTick{Now: 2150})
	scene := View(m)
	cp := chatrender.NewChatPainter()
	gtx := renderContext()
	sch := material.SchemeFor(material.Light)
	cp.PaintChatPane(gtx, scene.Chat, sch)
	if scene.Chat.DownProgress <= 0 {
		t.Fatalf("setup: the down button must be visible, progress = %v", scene.Chat.DownProgress)
	}
	if scene.Chat.DownBadgeText != "9" {
		t.Fatalf("badge = %q, want 9", scene.Chat.DownBadgeText)
	}
}

func TestDownBadgeResetsOnChatSwitch(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	m := downBadgeModel(t, 4, 7, unreadBarMsgs(nowMs))
	m, _ = Update(m, ChatLoaded{Msgs: []WireMessage{
		{ID: "11", SenderID: "u1", SenderName: "Alice", Text: "other", TimestampMs: nowMs, Status: 2},
	}, Items: FeedItems([]WireMessage{
		{ID: "11", SenderID: "u1", SenderName: "Alice", Text: "other", TimestampMs: nowMs, Status: 2},
	}, 0, time.UnixMilli(nowMs), false), Now: int(nowMs)})
	if s := View(m).Chat.DownBadgeText; s != "" {
		t.Fatalf("a chat switch without unread must clear the badge, got %q", s)
	}
}
