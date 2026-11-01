package gui

import (
	"reflect"
	"testing"

	"uniclient/engine"
)

func TestHeaderMenuSeparateDropsMainOnlyDialogs(t *testing.T) {
	dm := engine.ChatInfo{AccountID: "a", ChatID: "u1", Type: engine.ChatTypeDMVal, WallpaperJSON: "w"}
	for _, it := range headerMenuItems(dm, false, false, false, true, true) {
		switch it.id {
		case "notifsound", "autodelete", "gift", "theme", "wallpaper":
			t.Fatalf("separate windows never render the %q dialog surface — the row must be dropped (R30)", it.id)
		}
	}
	grp := engine.ChatInfo{AccountID: "a", ChatID: "g1", Type: engine.ChatTypeGroupVal}
	for _, it := range headerMenuItems(grp, false, false, false, false, true) {
		if it.id == "addmember" {
			t.Fatal("separate windows never render the add-member dialog — the row must be dropped (R30)")
		}
	}
	for _, dead := range []string{"notifsound", "autodelete", "gift", "theme", "wallpaper"} {
		if !containsAction(headerMenuItems(dm, false, false, false, true, false), dead) {
			t.Fatalf("main window lost the %q row", dead)
		}
	}
	if !containsAction(headerMenuItems(grp, false, false, false, false, false), "addmember") {
		t.Fatal("main window lost the addmember row")
	}
}

func TestMemberMenuSeparateDropsRestrictBan(t *testing.T) {
	chat := engine.ChatInfo{AccountID: "a", ChatID: "g", Type: engine.ChatTypeGroupVal, IsAdmin: true}
	m := engine.MemberInfo{UserID: "u2", Role: "member"}
	for _, it := range memberMenuItems(m, chat, "self", true) {
		if it.id == "restrict" || it.id == "ban" {
			t.Fatalf("separate windows never render the restrict/ban box — the %q row must be dropped (R30)", it.id)
		}
	}
	got := memberActions(memberMenuItems(m, chat, "self", false))
	if !reflect.DeepEqual(got, []string{"promote", "restrict", "ban", "remove"}) {
		t.Fatalf("main window member menu changed: %v", got)
	}
}

func TestSavedSublistMenuSeparateDropsDelete(t *testing.T) {
	if got := savedSublistMenuActions(false, false, false, true); len(got) != 1 || got[0] != "Pin" {
		t.Fatalf("separate windows must not offer Delete (confirm card is main-only): got %v (R30)", got)
	}
	if got := savedSublistMenuActions(true, true, true, true); len(got) != 3 {
		t.Fatalf("pinned separate menu must keep only Unpin/Move up/Move down: got %v", got)
	}
	if got := savedSublistMenuActions(false, false, false, false); len(got) != 2 || got[1] != "Delete messages" {
		t.Fatalf("main window lost the Delete entry: %v", got)
	}
}

func TestAttachMenuSeparateDropsContentPanes(t *testing.T) {
	sep := &App{separate: &chatKey{AccountID: "a", ChatID: "c"}}
	for _, it := range sep.attachMenuItems() {
		switch it.label {
		case "Music", "Location", "Contact":
			t.Fatalf("attach item %q opens a main-window content pane — dead in separate windows (R30)", it.label)
		}
	}
	main := &App{}
	have := map[string]bool{}
	for _, it := range main.attachMenuItems() {
		have[it.label] = true
	}
	for _, want := range []string{"Photo or Video", "Music", "File", "Poll", "Location", "Contact"} {
		if !have[want] {
			t.Fatalf("main window attach menu lost %q", want)
		}
	}
}

func TestCallBarInCall(t *testing.T) {
	chat := engine.ChatInfo{AccountID: "a", ChatID: "c1"}
	if callBarInCall(chat, nil) {
		t.Fatal("no joined call → JOIN state")
	}
	if callBarInCall(chat, &joinedCall{accountID: "a", chatID: "other"}) {
		t.Fatal("a joined call on another chat is not this bar's call")
	}
	if !callBarInCall(chat, &joinedCall{accountID: "a", chatID: "c1"}) {
		t.Fatal("this chat's joined call must flip the bar to the in-call state")
	}
	if callBarInCall(chat, &joinedCall{accountID: "other", chatID: "c1"}) {
		t.Fatal("chatIDs are per-account — another account's chat is not this bar's call")
	}
}

func TestApplyCallJoinSeparateSkipsVoiceFlip(t *testing.T) {
	sep := &App{separate: &chatKey{AccountID: "a", ChatID: "c"}, eng: &engine.Engine{}}
	sep.applyCallJoinResult(engine.ChatInfo{AccountID: "a", ChatID: "c", Title: "T"}, "call1", nil)
	if sep.mode != 0 {
		t.Fatalf("separate windows have no voice tab — mode must stay 0, got %d (R30)", sep.mode)
	}
	if sep.joinedGC == nil || sep.joinedGC.callID != "call1" {
		t.Fatal("the joined-call state (the bar's LEAVE state) must land in separate windows")
	}

	main := &App{eng: &engine.Engine{}}
	main.applyCallJoinResult(engine.ChatInfo{AccountID: "a", ChatID: "c", Title: "T"}, "call1", nil)
	if main.mode != 1 {
		t.Fatalf("main window must still flip to the voice tab, got mode %d", main.mode)
	}
}

func TestMainOnlySurfaceShown(t *testing.T) {
	sep := &App{separate: &chatKey{AccountID: "a", ChatID: "c"}}
	if mainOnlySurfaceShown(sep) {
		t.Fatal("separate windows never render content-pane dialogs, the settings/voice pages, or the main-branch modals (R30)")
	}
	if !mainOnlySurfaceShown(&App{}) {
		t.Fatal("the main window renders all of them")
	}
}
