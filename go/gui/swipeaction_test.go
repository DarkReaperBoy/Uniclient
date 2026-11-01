package gui

import (
	"math"
	"testing"

	"uniclient/engine"
)

func TestSwipeDirLock(t *testing.T) {
	cases := []struct {
		name   string
		dx, dy float32
		want   int
	}{
		{"still", 0, 0, 0},
		{"tiny jitters", 0.5, 0.5, 0},
		{"right wins", 5, 1, 1},
		{"left wins", -5, 1, -1},
		{"vertical", 1, 5, 0},
		{"diagonal-ish", 3, 3, 0},
	}
	for _, c := range cases {
		if got := swipeDirLock(c.dx, c.dy); got != c.want {
			t.Errorf("%s: swipeDirLock(%v,%v) = %d, want %d", c.name, c.dx, c.dy, got, c.want)
		}
	}
}

func TestSwipeRatio(t *testing.T) {
	thr := float32(50)
	cases := []struct {
		dx   float32
		want float32
	}{
		{0, 0},
		{-30, 0},
		{25, 0.5},
		{50, 1},
		{75, 1.5},
		{200, 1.5},
	}
	for _, c := range cases {
		if got := swipeRatio(c.dx, thr); math.Abs(float64(got-c.want)) > 1e-6 {
			t.Errorf("swipeRatio(%v) = %v, want %v", c.dx, got, c.want)
		}
	}
}

func TestSwipeTranslation(t *testing.T) {
	thr := float32(50)
	if tr := swipeTranslation(0.5, thr); math.Abs(float64(tr-25)) > 1e-6 {
		t.Errorf("translation(0.5) = %v, want 25", tr)
	}
	if tr := swipeTranslation(1, thr); math.Abs(float64(tr-50)) > 1e-6 {
		t.Errorf("translation(1.0) = %v, want 50", tr)
	}
	tr1 := swipeTranslation(1.1, thr)
	tr2 := swipeTranslation(1.5, thr)
	if tr1 <= 50 || tr2 <= tr1 {
		t.Errorf("overswipe must grow damped: 1.1→%v 1.5→%v", tr1, tr2)
	}
	if tr2 >= 75 {
		t.Errorf("overswipe damped below linear: %v >= 75", tr2)
	}
	if tr := swipeTranslation(0, thr); tr != 0 {
		t.Errorf("translation(0) = %v, want 0", tr)
	}
	if tr := swipeTranslation(-0.4, thr); tr != 0 {
		t.Errorf("translation(-0.4) = %v, want 0", tr)
	}
}

func TestSwipeFires(t *testing.T) {
	if swipeFires(0.99) {
		t.Error("0.99 must not fire")
	}
	if !swipeFires(1.0) {
		t.Error("1.0 must fire")
	}
	if !swipeFires(1.3) {
		t.Error("1.3 must fire")
	}
}

func TestSwipeBackCommand(t *testing.T) {
	cases := []struct {
		name                string
		archiveView, folder bool
		want                string
	}{
		{"nothing open", false, false, ""},
		{"archive view", true, false, "archive"},
		{"folder tab", false, true, "folder"},
		{"archive beats folder", true, true, "archive"},
	}
	for _, c := range cases {
		if got := swipeBackCommand(c.archiveView, c.folder); got != c.want {
			t.Errorf("%s: swipeBackCommand = %q, want %q", c.name, got, c.want)
		}
	}
}

func TestResolveSwipeAction(t *testing.T) {
	muted := engine.ChatInfo{IsMuted: true}
	live := engine.ChatInfo{}
	unread := engine.ChatInfo{UnreadCount: 4}
	marked := engine.ChatInfo{UnreadMark: true}
	pinned := engine.ChatInfo{IsPinned: true}
	archived := engine.ChatInfo{IsArchived: true}

	if a := resolveSwipeAction("mute", live, false); a.label != "Mute" || a.done != "Muted" {
		t.Errorf("mute/live: %+v", a)
	}
	if a := resolveSwipeAction("mute", muted, false); a.label != "Unmute" || a.done != "Unmuted" {
		t.Errorf("mute/muted: %+v", a)
	}

	if a := resolveSwipeAction("pin", live, false); a.label != "Pin" || a.done != "Pinned" {
		t.Errorf("pin/live: %+v", a)
	}
	if a := resolveSwipeAction("pin", pinned, false); a.label != "Unpin" || a.done != "Unpinned" {
		t.Errorf("pin/pinned: %+v", a)
	}

	if a := resolveSwipeAction("read", unread, false); a.label != "Mark as read" {
		t.Errorf("read/unread: %+v", a)
	}
	if a := resolveSwipeAction("read", marked, false); a.label != "Mark as read" {
		t.Errorf("read/marked: %+v", a)
	}
	if a := resolveSwipeAction("read", live, false); a.label != "Mark as unread" {
		t.Errorf("read/live: %+v", a)
	}

	if a := resolveSwipeAction("archive", live, false); a.label != "Archive" || a.done != "Archived" {
		t.Errorf("archive/live: %+v", a)
	}
	if a := resolveSwipeAction("archive", archived, false); a.label != "Unarchive" || a.done != "Unarchived" {
		t.Errorf("archive/archived: %+v", a)
	}
	if a := resolveSwipeAction("archive", live, true); a.label != "Unarchive" {
		t.Errorf("archive view row: %+v", a)
	}

	if a := resolveSwipeAction("delete", live, false); a.label != "Delete" || !a.red {
		t.Errorf("delete: %+v", a)
	}

	if a := resolveSwipeAction("disabled", live, false); a.label != "Disabled" || !a.gray || a.kind != "" {
		t.Errorf("disabled: %+v", a)
	}
	if a := resolveSwipeAction("", live, false); a.label != "Disabled" || a.kind != "" {
		t.Errorf("empty config: %+v", a)
	}

	if a := resolveSwipeAction("bogus", live, false); a.kind != "" {
		t.Errorf("bogus config: %+v", a)
	}
}

func TestSwipeLabelFits(t *testing.T) {
	cases := []struct {
		revealDp float32
		wantMax  int
	}{
		{160, 14},
		{80, 14},
		{40, 12},
		{16, 8},
		{6, 6},
	}
	for _, c := range cases {
		sp := swipeLabelSize(c.revealDp)
		if sp > c.wantMax || sp < 5 {
			t.Errorf("swipeLabelSize(%v) = %v, want in [5,%d]", c.revealDp, sp, c.wantMax)
		}
	}
	if sp := swipeLabelSize(200); sp != 14 {
		t.Errorf("wide reveal label size = %v, want 14", sp)
	}
	if sp := swipeLabelSize(2); sp != 5 {
		t.Errorf("tiny reveal label size = %v, want 5", sp)
	}
}
