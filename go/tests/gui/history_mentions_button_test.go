package tests

import (
	"testing"

	. "uniclient/ui/app"
)

func mentionsModel(t *testing.T, mentionRow, n int) Model {
	t.Helper()
	items := downChatItems(n)
	if mentionRow >= 0 && mentionRow < n {
		items[mentionRow].UnreadMention = true
	}
	return downModel(t, items)
}

func TestChatMentionsHiddenOnPlainChat(t *testing.T) {
	m := mentionsModel(t, -1, 40)
	if m.ChatMentions.Shown || m.ChatMentions.Anim || m.ChatMentions.Progress != 0 {
		t.Fatalf("plain chat: %+v, want hidden and settled", m.ChatMentions)
	}
	if m.ChatMentionsActive() {
		t.Fatalf("ChatMentionsActive true with no mentions")
	}
}

func TestChatMentionsShowOnLoad(t *testing.T) {
	m := mentionsModel(t, 12, 40)
	if !m.ChatMentions.Shown || !m.ChatMentions.Anim || m.ChatMentions.Progress != 0 {
		t.Fatalf("after load with mention: %+v, want shown animating from 0", m.ChatMentions)
	}
	if !m.ChatMentionsActive() {
		t.Fatalf("ChatMentionsActive false while animating")
	}
}

func TestChatMentionsAnimates(t *testing.T) {
	m := mentionsModel(t, 12, 40)
	if m.ChatMentions.Started != 0 {
		t.Fatalf("anim start = %d, want 0 (clocked at ChatLoaded arrival)", m.ChatMentions.Started)
	}
	m, _ = Update(m, ChatTick{Now: 75})
	if m.ChatMentions.Progress != 0.5 {
		t.Fatalf("mid progress = %v, want 0.5", m.ChatMentions.Progress)
	}
	m, _ = Update(m, ChatTick{Now: 150})
	if m.ChatMentions.Progress != 1 || m.ChatMentions.Anim || m.ChatMentionsActive() {
		t.Fatalf("end progress = %v anim=%v, want 1 settled", m.ChatMentions.Progress, m.ChatMentions.Anim)
	}
}

func TestChatMentionsDoNotRideScroll(t *testing.T) {
	m := mentionsModel(t, 12, 40)
	m, _ = Update(m, ChatTick{Now: 250})
	m = chatScrollTo(m, 0, 300)
	m = chatScrollTo(m, 1880, 400)
	if !m.ChatMentions.Shown || m.ChatMentions.Progress != 1 {
		t.Fatalf("after scrolling away: %+v, want still shown settled — visibility is data-driven",
			m.ChatMentions)
	}
}

func TestChatMentionsClickJumpsToFirstMention(t *testing.T) {
	m := mentionsModel(t, 12, 40)
	m, _ = Update(m, ChatTick{Now: 250})
	m = chatScrollTo(m, 1880, 300)
	m, _ = Update(m, ChatTick{Now: 450})
	if m.ChatDown.Progress != 0 {
		t.Fatalf("down still shown %v, want settled hidden before clicking mentions", m.ChatDown.Progress)
	}
	m, _ = Update(m, ChatPressed{X: 750, Y: 80, Now: 500})
	m, _ = Update(m, ChatReleased{X: 750, Y: 80, Now: 510})
	if m.ChatScroll.Top != 600 {
		t.Fatalf("after click top = %d, want 600 (first unread mention row 12)", m.ChatScroll.Top)
	}
	if !m.ChatMentions.Shown {
		t.Fatalf("after jump: hidden, want shown — no read-marking in the model yet")
	}
}

func TestChatMentionsClickClampsToMax(t *testing.T) {
	m := mentionsModel(t, 39, 40)
	m, _ = Update(m, ChatTick{Now: 250})
	m = chatScrollTo(m, 1880, 300)
	m, _ = Update(m, ChatTick{Now: 450})
	m, _ = Update(m, ChatPressed{X: 750, Y: 80, Now: 500})
	m, _ = Update(m, ChatReleased{X: 750, Y: 80, Now: 510})
	if m.ChatScroll.Top != 1880 {
		t.Fatalf("after click top = %d, want 1880 (clamped)", m.ChatScroll.Top)
	}
}

func TestChatMentionsStackedAboveDownClick(t *testing.T) {
	m := mentionsModel(t, 12, 40)
	m, _ = Update(m, ChatTick{Now: 250})
	if m.ChatDown.Progress != 1 {
		t.Fatalf("down progress %v, want 1 shown at load (scrolled to top)", m.ChatDown.Progress)
	}
	m, _ = Update(m, ChatPressed{X: 750, Y: 20, Now: 500})
	m, _ = Update(m, ChatReleased{X: 750, Y: 20, Now: 510})
	if m.ChatScroll.Top != 600 {
		t.Fatalf("stacked click top = %d, want 600 (mention jump from the stacked slot)", m.ChatScroll.Top)
	}
}

func TestChatMentionsDragCancelsClick(t *testing.T) {
	m := mentionsModel(t, 12, 40)
	m, _ = Update(m, ChatTick{Now: 250})
	m = chatScrollTo(m, 1880, 300)
	m, _ = Update(m, ChatTick{Now: 450})
	m, _ = Update(m, ChatPressed{X: 750, Y: 80, Now: 500})
	m, _ = Update(m, ChatDragged{X: 400, Y: 400, Now: 520})
	m, _ = Update(m, ChatReleased{X: 400, Y: 400, Now: 530})
	if m.ChatScroll.Top != 1880 {
		t.Fatalf("drag-cancelled click moved top to %d, want 1880 (unchanged)", m.ChatScroll.Top)
	}
}

func TestChatMentionsReleaseOutsideCancelsClick(t *testing.T) {
	m := mentionsModel(t, 12, 40)
	m, _ = Update(m, ChatTick{Now: 250})
	m = chatScrollTo(m, 1880, 300)
	m, _ = Update(m, ChatTick{Now: 450})
	m, _ = Update(m, ChatPressed{X: 750, Y: 80, Now: 500})
	m, _ = Update(m, ChatDragged{X: 750, Y: 79, Now: 510})
	m, _ = Update(m, ChatReleased{X: 700, Y: 40, Now: 520})
	if m.ChatScroll.Top != 1880 {
		t.Fatalf("outside release moved top to %d, want 1880 (unchanged)", m.ChatScroll.Top)
	}
}

func TestChatMentionsTouchTapJumps(t *testing.T) {
	m := mentionsModel(t, 12, 40)
	m, _ = Update(m, ChatTick{Now: 250})
	m = chatScrollTo(m, 1880, 300)
	m, _ = Update(m, ChatTick{Now: 450})
	m, _ = Update(m, ChatPressed{X: 750, Y: 80, Touch: true, Now: 500})
	if m.ChatTouch.Active {
		t.Fatalf("touch press on mentions button started a touch drag, want button press only")
	}
	if m.ChatPress.Row != -1 {
		t.Fatalf("touch press on mentions button selected row %d, want -1", m.ChatPress.Row)
	}
	m, _ = Update(m, ChatReleased{X: 750, Y: 80, Now: 540})
	if m.ChatScroll.Top != 600 {
		t.Fatalf("touch tap top = %d, want 600", m.ChatScroll.Top)
	}
}

func TestChatMentionsTouchDragFromButtonDoesNotScroll(t *testing.T) {
	m := mentionsModel(t, 12, 40)
	m, _ = Update(m, ChatTick{Now: 250})
	m = chatScrollTo(m, 1880, 300)
	m, _ = Update(m, ChatTick{Now: 450})
	m, _ = Update(m, ChatPressed{X: 750, Y: 80, Touch: true, Now: 500})
	m, _ = Update(m, ChatDragged{X: 750, Y: 260, Now: 560})
	m, _ = Update(m, ChatReleased{X: 750, Y: 260, Now: 600})
	if m.ChatScroll.Top != 1880 {
		t.Fatalf("touch drag from mentions button scrolled to %d, want 1880 (button grabs)", m.ChatScroll.Top)
	}
}

func TestChatMentionsResetsOnChatSwitch(t *testing.T) {
	m := mentionsModel(t, 12, 40)
	m, _ = Update(m, ChatTick{Now: 250})
	m, _ = Update(m, ChatLoaded{Items: downChatItems(2)})
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(2, 50)})
	if m.ChatMentions.Shown || m.ChatMentions.Progress != 0 || m.ChatMentions.Anim {
		t.Fatalf("after chat switch: %+v, want reset hidden settled", m.ChatMentions)
	}
}

func TestChatMentionsPrependKeepsShown(t *testing.T) {
	m := mentionsModel(t, 12, 40)
	m, _ = Update(m, ChatTick{Now: 250})
	m, _ = Update(m, ChatPrepended{Msgs: preloadMsgs(5, 1000000), MoreAbove: true})
	if !m.ChatMentions.Shown || m.ChatMentions.Progress != 1 {
		t.Fatalf("after prepend: %+v, want still shown settled", m.ChatMentions)
	}
}

func TestChatMentionsPaneProgress(t *testing.T) {
	m := mentionsModel(t, 12, 40)
	m, _ = Update(m, ChatTick{Now: 75})
	if s := View(m); s.Chat.MentionsProgress != m.ChatMentions.Progress {
		t.Fatalf("pane progress = %v, want %v", s.Chat.MentionsProgress, m.ChatMentions.Progress)
	}
	m, _ = Update(m, ChatTick{Now: 150})
	s := View(m)
	if s.Chat.MentionsProgress != 1 {
		t.Fatalf("pane progress = %v, want 1", s.Chat.MentionsProgress)
	}
	if s.Chat.DownProgress != 1 {
		t.Fatalf("down progress = %v, want 1 (both buttons coexist in the stack)", s.Chat.DownProgress)
	}
}
