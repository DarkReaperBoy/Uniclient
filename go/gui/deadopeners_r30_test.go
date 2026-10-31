package gui

import (
	"reflect"
	"testing"

	"uniclient/engine"
)

// R30 — the R29 systemic sweep: which openers reachable from surfaces that
// render in EVERY window (header menu, attach menu, message menu, info
// panel + member menu, boost panel, call overlay, saved-lists pane,
// shortcuts, call bar) set state that ONLY layoutMain paints (content-pane
// dialogs, the settings/voice pages, the main-branch window modals)? Every
// one of those is a shown-but-dead button in a separate chat window —
// forbidden by §1.10 ("what cannot work is HIDDEN, never faked"). The pure
// derivation functions take a `separate` flag and drop the dead rows; the
// inline gates use mainOnlySurfaceShown (R29's profileMusicSectionShown
// shape, made the shared predicate of the class).

// headerMenuItems must drop every row whose action opens a main-window
// content pane (sound picker, TTL, chat theme, wallpaper, gift picker,
// add-member) — the header menu renders in every window, the dialogs do not.
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
	// The main window keeps every one of them.
	for _, dead := range []string{"notifsound", "autodelete", "gift", "theme", "wallpaper"} {
		if !containsAction(headerMenuItems(dm, false, false, false, true, false), dead) {
			t.Fatalf("main window lost the %q row", dead)
		}
	}
	if !containsAction(headerMenuItems(grp, false, false, false, false, false), "addmember") {
		t.Fatal("main window lost the addmember row")
	}
}

// memberMenuItems must drop Restrict/Ban in separate windows (the boxes are
// main-branch window modals); the direct engine actions (promote, demote,
// remove, unban) stay — they work from any window.
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

// savedSublistMenuActions must drop the destructive "Delete messages" entry
// in separate windows (its confirm card is a main-branch window modal);
// pin/move stay — they are direct engine actions.
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

// attachMenuItems must drop Music/Location/Contact in separate windows (all
// three open content-pane dialogs); Photo/File (system pickers) and Poll
// (a chat-view overlay) stay.
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

// callBarInCall drives the separate-window call bar: JOIN joins (engine +
// joined-call state) without the Voice-tab flip (mode 1 paints only in
// layoutMain), and once THIS window has joined THIS chat's call the bar
// becomes the in-call surface (LEAVE).
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

// applyCallJoinResult: in a separate window the join must NOT flip the
// Voice tab (mode 1 is a layoutMain-only surface — the flip painted
// nothing); the joined-call state (the bar's LEAVE state) must still land.
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

// mainOnlySurfaceShown is the shared R30 predicate (R29's
// profileMusicSectionShown shape): it gates every inline opener whose
// target surface only layoutMain paints — the mute-duration clock, the
// "Filter Like This…" row, the prepaid-giveaway launch cells, the call
// rating dialog, and the Ctrl+J contacts shortcut.
func TestMainOnlySurfaceShown(t *testing.T) {
	sep := &App{separate: &chatKey{AccountID: "a", ChatID: "c"}}
	if mainOnlySurfaceShown(sep) {
		t.Fatal("separate windows never render content-pane dialogs, the settings/voice pages, or the main-branch modals (R30)")
	}
	if !mainOnlySurfaceShown(&App{}) {
		t.Fatal("the main window renders all of them")
	}
}
