package tests

import (
	"testing"

	. "uniclient/ui/app"
)

func reactionsModel(t *testing.T, reactionRow, mentionRow, n int) Model {
	t.Helper()
	items := downChatItems(n)
	if reactionRow >= 0 && reactionRow < n {
		items[reactionRow].UnreadReaction = true
	}
	if mentionRow >= 0 && mentionRow < n {
		items[mentionRow].UnreadMention = true
	}
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 400})
	m.HasDialogs = false
	m, _ = Update(m, ChatLoaded{Items: items})
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(len(items), 50)})
	return m
}

func reactionsScrollTo(m Model, top, now int) Model {
	m, _ = Update(m, ChatScrolled{DeltaY: top - m.ChatScroll.Top, Now: now})
	return m
}

func TestChatReactionsHiddenOnPlainChat(t *testing.T) {
	m := reactionsModel(t, -1, -1, 40)
	if m.ChatReactions.Shown || m.ChatReactions.Anim || m.ChatReactions.Progress != 0 {
		t.Fatalf("plain chat: %+v, want hidden and settled", m.ChatReactions)
	}
	if m.ChatReactionsActive() {
		t.Fatalf("ChatReactionsActive true with no reactions")
	}
}

func TestChatReactionsShowOnLoad(t *testing.T) {
	m := reactionsModel(t, 7, -1, 40)
	if !m.ChatReactions.Shown || !m.ChatReactions.Anim || m.ChatReactions.Progress != 0 {
		t.Fatalf("after load with reaction: %+v, want shown animating from 0", m.ChatReactions)
	}
	if !m.ChatReactionsActive() {
		t.Fatalf("ChatReactionsActive false while animating")
	}
}

func TestChatReactionsAnimates(t *testing.T) {
	m := reactionsModel(t, 7, -1, 40)
	if m.ChatReactions.Started != 0 {
		t.Fatalf("anim start = %d, want 0 (clocked at ChatLoaded arrival)", m.ChatReactions.Started)
	}
	m, _ = Update(m, ChatTick{Now: 75})
	if m.ChatReactions.Progress != 0.5 {
		t.Fatalf("mid progress = %v, want 0.5", m.ChatReactions.Progress)
	}
	m, _ = Update(m, ChatTick{Now: 150})
	if m.ChatReactions.Progress != 1 || m.ChatReactions.Anim || m.ChatReactionsActive() {
		t.Fatalf("end progress = %v anim=%v, want 1 settled", m.ChatReactions.Progress, m.ChatReactions.Anim)
	}
}

func TestChatReactionsDoNotRideScroll(t *testing.T) {
	m := reactionsModel(t, 7, -1, 40)
	m, _ = Update(m, ChatTick{Now: 150})
	m = reactionsScrollTo(m, 0, 200)
	m = reactionsScrollTo(m, 1600, 300)
	if !m.ChatReactions.Shown || m.ChatReactions.Progress != 1 {
		t.Fatalf("after scrolling away: %+v, want still shown settled — visibility is data-driven",
			m.ChatReactions)
	}
}

func TestChatReactionsClickJumpsToFirstReaction(t *testing.T) {
	m := reactionsModel(t, 7, -1, 40)
	m, _ = Update(m, ChatTick{Now: 150})
	if m.ChatDown.Progress != 1 {
		t.Fatalf("down %v, want shown settled at load (reactions rides its slot)", m.ChatDown.Progress)
	}
	m, _ = Update(m, ChatPressed{X: 750, Y: 290, Now: 400})
	m, _ = Update(m, ChatReleased{X: 750, Y: 290, Now: 410})
	if m.ChatScroll.Top != 350 {
		t.Fatalf("after click top = %d, want 350 (first unread reaction row 7)", m.ChatScroll.Top)
	}
	if !m.ChatReactions.Shown {
		t.Fatalf("after jump: hidden, want shown — no read-marking in the model yet")
	}
}

func TestChatReactionsClickClampsToMax(t *testing.T) {
	m := reactionsModel(t, 39, -1, 40)
	m, _ = Update(m, ChatTick{Now: 150})
	m, _ = Update(m, ChatPressed{X: 750, Y: 290, Now: 400})
	m, _ = Update(m, ChatReleased{X: 750, Y: 290, Now: 410})
	if m.ChatScroll.Top != 1600 {
		t.Fatalf("after click top = %d, want 1600 (clamped)", m.ChatScroll.Top)
	}
}

func TestChatReactionsFullStackClick(t *testing.T) {
	m := reactionsModel(t, 7, 12, 40)
	m, _ = Update(m, ChatTick{Now: 150})
	if m.ChatDown.Progress != 1 || m.ChatMentions.Progress != 1 || m.ChatReactions.Progress != 1 {
		t.Fatalf("stack %+v %+v %+v, want all three settled shown at load (scrolled to top)",
			m.ChatDown, m.ChatMentions, m.ChatReactions)
	}
	m, _ = Update(m, ChatPressed{X: 750, Y: 220, Now: 400})
	m, _ = Update(m, ChatReleased{X: 750, Y: 220, Now: 410})
	if m.ChatScroll.Top != 350 {
		t.Fatalf("full-stack click top = %d, want 350 (reaction jump from the top stack slot)", m.ChatScroll.Top)
	}
}

func TestChatReactionsDragCancelsClick(t *testing.T) {
	m := reactionsModel(t, 7, -1, 40)
	m, _ = Update(m, ChatTick{Now: 150})
	m, _ = Update(m, ChatPressed{X: 750, Y: 290, Now: 400})
	m, _ = Update(m, ChatDragged{X: 400, Y: 400, Now: 420})
	m, _ = Update(m, ChatReleased{X: 400, Y: 400, Now: 430})
	if m.ChatScroll.Top != 0 {
		t.Fatalf("drag-cancelled click moved top to %d, want 0 (unchanged)", m.ChatScroll.Top)
	}
}

func TestChatReactionsReleaseOutsideCancelsClick(t *testing.T) {
	m := reactionsModel(t, 7, -1, 40)
	m, _ = Update(m, ChatTick{Now: 150})
	m, _ = Update(m, ChatPressed{X: 750, Y: 290, Now: 400})
	m, _ = Update(m, ChatDragged{X: 750, Y: 289, Now: 410})
	m, _ = Update(m, ChatReleased{X: 700, Y: 40, Now: 420})
	if m.ChatScroll.Top != 0 {
		t.Fatalf("outside release moved top to %d, want 0 (unchanged)", m.ChatScroll.Top)
	}
}

func TestChatReactionsTouchTapJumps(t *testing.T) {
	m := reactionsModel(t, 7, -1, 40)
	m, _ = Update(m, ChatTick{Now: 150})
	m, _ = Update(m, ChatPressed{X: 750, Y: 290, Touch: true, Now: 400})
	if m.ChatTouch.Active {
		t.Fatalf("touch press on reactions button started a touch drag, want button press only")
	}
	if m.ChatPress.Row != -1 {
		t.Fatalf("touch press on reactions button selected row %d, want -1", m.ChatPress.Row)
	}
	m, _ = Update(m, ChatReleased{X: 750, Y: 290, Now: 440})
	if m.ChatScroll.Top != 350 {
		t.Fatalf("touch tap top = %d, want 350", m.ChatScroll.Top)
	}
}

func TestChatReactionsTouchDragFromButtonDoesNotScroll(t *testing.T) {
	m := reactionsModel(t, 7, -1, 40)
	m, _ = Update(m, ChatTick{Now: 150})
	m, _ = Update(m, ChatPressed{X: 750, Y: 290, Touch: true, Now: 400})
	m, _ = Update(m, ChatDragged{X: 750, Y: 60, Now: 460})
	m, _ = Update(m, ChatReleased{X: 750, Y: 60, Now: 500})
	if m.ChatScroll.Top != 0 {
		t.Fatalf("touch drag from reactions button scrolled to %d, want 0 (button grabs)", m.ChatScroll.Top)
	}
}

func TestChatReactionsResetsOnChatSwitch(t *testing.T) {
	m := reactionsModel(t, 7, -1, 40)
	m, _ = Update(m, ChatTick{Now: 150})
	m, _ = Update(m, ChatLoaded{Items: downChatItems(2)})
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(2, 50)})
	if m.ChatReactions.Shown || m.ChatReactions.Progress != 0 || m.ChatReactions.Anim {
		t.Fatalf("after chat switch: %+v, want reset hidden settled", m.ChatReactions)
	}
}

func TestChatReactionsPrependKeepsShown(t *testing.T) {
	m := reactionsModel(t, 7, -1, 40)
	m, _ = Update(m, ChatTick{Now: 150})
	m, _ = Update(m, ChatPrepended{Msgs: preloadMsgs(5, 1000000), MoreAbove: true})
	if !m.ChatReactions.Shown || m.ChatReactions.Progress != 1 {
		t.Fatalf("after prepend: %+v, want still shown settled", m.ChatReactions)
	}
}

func TestChatReactionsPaneProgress(t *testing.T) {
	m := reactionsModel(t, 7, 12, 40)
	m, _ = Update(m, ChatTick{Now: 75})
	if s := View(m); s.Chat.ReactionsProgress != m.ChatReactions.Progress {
		t.Fatalf("pane progress = %v, want %v", s.Chat.ReactionsProgress, m.ChatReactions.Progress)
	}
	m, _ = Update(m, ChatTick{Now: 150})
	s := View(m)
	if s.Chat.ReactionsProgress != 1 || s.Chat.MentionsProgress != 1 || s.Chat.DownProgress != 1 {
		t.Fatalf("pane stack = %v/%v/%v, want 1/1/1 (all three coexist)",
			s.Chat.ReactionsProgress, s.Chat.MentionsProgress, s.Chat.DownProgress)
	}
}
