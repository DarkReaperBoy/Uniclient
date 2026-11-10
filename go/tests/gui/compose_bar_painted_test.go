package tests

import (
	"testing"
	"time"

	. "uniclient/ui/app"
)

func TestOpenedChatCarriesComposePane(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	row := snapshotChats(nowMs, "77", "Alice", "hi there", 1, "", false, 0, 0, false)
	m := applyEngineEvent(t, feedsModel(t, 1440, 900).WithPort(&fakeChatPort{ok: true}), chatSnapshotWire("tele_02", row, nowMs))
	m, cmd := Update(m, DialogsPressed{X: 20, Y: 10, Now: 1})
	loaded, ok := cmd().(ChatLoaded)
	if !ok {
		t.Fatalf("the press must fire the open cmd, got %T", cmd())
	}
	m, _ = Update(m, loaded)
	if !m.ChatCompose.CanSend {
		t.Fatalf("the opened chat must arm the compose bar")
	}
	scene := View(m)
	if !scene.Chat.Compose.Shown {
		t.Fatalf("the scene must carry the compose pane for a CanSend chat")
	}
}
