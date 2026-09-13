package gui

import (
	"strings"
	"testing"
	"time"

	"uniclient/engine"
	"uniclient/utils"
)

// ── stripZalgo (AyuGram ayu_helpers.cpp filterZalgo, slice 173) ──────────
//
// Pattern: \p{Mn}{3,}|[ bidi controls ] — runs of 3+ combining marks lose
// the tail (first two kept), bidi override/embedding controls vanish.

func TestStripZalgoLeansTexts(t *testing.T) {
	clean := "hello world"
	if got := stripZalgo(clean); got != clean {
		t.Errorf("clean text changed: %q", got)
	}
	// Normal accents are 1-2 combining marks — untouched.
	accented := "café naïve"
	if got := stripZalgo(accented); got != accented {
		t.Errorf("accented text changed: %q", got)
	}
	if got := stripZalgo("👍 emoji text 👌"); got != "👍 emoji text 👌" {
		t.Errorf("emoji text changed: %q", got)
	}
}

func TestStripZalgoTrimsLongCombiningRuns(t *testing.T) {
	// e + 5 combining marks → e + 2 kept.
	zalgo := "e\u0301\u0302\u0303\u0304\u0305"
	got := stripZalgo(zalgo)
	if want := "e\u0301\u0302"; got != want {
		t.Errorf("zalgo run = %q, want %q", got, want)
	}
	// Mixed sentence: zalgo word collapses, rest survives.
	in := "hi z\u0301\u0302\u0303\u0304 there"
	if got := stripZalgo(in); got != "hi z\u0301\u0302 there" {
		t.Errorf("mixed = %q", got)
	}
}

func TestStripZalgoDropsBidiControls(t *testing.T) {
	for _, c := range []rune{'\u202A', '\u202E', '\u2066', '\u2069', '\u200E', '\u200F', '\u061C'} {
		in := "a" + string(c) + "b"
		if got := stripZalgo(in); got != "ab" {
			t.Errorf("bidi control %U not stripped: %q", c, got)
		}
	}
}

func TestStripZalgoFastPathIdentity(t *testing.T) {
	// No changes → the original string must be returned as-is.
	s := "plain ascii"
	if got := stripZalgo(s); got != s {
		t.Errorf("fast path changed the string")
	}
	if strings.Contains(stripZalgo("x\u0301\u0302\u0303"), "\u0303") {
		t.Error("third combining mark must be dropped")
	}
}

// ── message seconds (ayu showMessageSeconds, formatMessageTime) ─────────

func TestMsgTimeLabel(t *testing.T) {
	if got := msgTimeLabel(0); got != "" {
		t.Errorf("zero ts = %q, want empty", got)
	}
	ms := time.Date(2026, 9, 13, 15, 4, 23, 0, time.UTC).UnixMilli()
	setMsgShowSeconds(false)
	if got := msgTimeLabel(ms); got != "15:04" {
		t.Errorf("seconds off = %q, want 15:04", got)
	}
	setMsgShowSeconds(true)
	if got := msgTimeLabel(ms); got != "15:04:23" {
		t.Errorf("seconds on = %q, want 15:04:23", got)
	}
	setMsgShowSeconds(false) // restore default for other tests
}

// ── reaction-strip visibility (ayu show{Channel,Group,Private}Reactions) ─

func TestReactionsVisible(t *testing.T) {
	// AyuGram defaults: all three ON. The snapshot carries effective
	// values, so zero-value cfgSnapshot{} means hidden and all-true means
	// shown — the nil→true fold is pinned by cfgFromAppConfig tests.
	allOn := cfgSnapshot{AyuReactChannels: true, AyuReactGroups: true, AyuReactPrivate: true}
	chanRow := engine.ChatInfo{Type: engine.ChatTypeChanVal}
	groupRow := engine.ChatInfo{Type: engine.ChatTypeGroupVal}
	dmRow := engine.ChatInfo{Type: engine.ChatTypeDMVal}
	if !reactionsVisible(chanRow, allOn) || !reactionsVisible(groupRow, allOn) || !reactionsVisible(dmRow, allOn) {
		t.Error("all toggles on: every chat type shows reactions")
	}
	if reactionsVisible(chanRow, cfgSnapshot{}) {
		t.Error("explicit false (zero snapshot): channels hide the strip")
	}
	if !reactionsVisible(dmRow, cfgSnapshot{AyuReactPrivate: true}) {
		t.Error("private on: DM shows the strip")
	}
	if reactionsVisible(dmRow, cfgSnapshot{AyuReactChannels: true, AyuReactGroups: true}) {
		t.Error("private off: DM must hide the strip")
	}
	if !reactionsVisible(groupRow, cfgSnapshot{AyuReactGroups: true}) {
		t.Error("groups on: group shows the strip")
	}
	if !reactionsVisible(chanRow, cfgSnapshot{AyuReactChannels: true}) {
		t.Error("channels on: channel shows the strip")
	}
}

// ── send confirmations (ayu sticker/gif/voice Confirmation) ──────────────

func TestConfirmKindTitle(t *testing.T) {
	if got := confirmKindTitle("sticker"); got != "Send this sticker?" {
		t.Errorf("sticker title = %q", got)
	}
	if got := confirmKindTitle("gif"); got != "Send this GIF?" {
		t.Errorf("gif title = %q", got)
	}
	if got := confirmKindTitle("voice"); got != "Send this voice message?" {
		t.Errorf("voice title = %q", got)
	}
	if got := confirmKindTitle("unknown"); got == "" {
		t.Error("unknown kind needs a title too")
	}
}

// Config dispatch: the eight new ayu keys reach the engine bridge.
func TestConfigFieldChangesAyuExtras(t *testing.T) {
	keys := []string{
		"ayu_msg_seconds", "ayu_filter_zalgo",
		"ayu_react_channels", "ayu_react_groups", "ayu_react_private",
		"ayu_confirm_sticker", "ayu_confirm_gif", "ayu_confirm_voice",
	}
	for _, k := range keys {
		c := configFieldChanges(k, true)
		if c == nil {
			t.Fatalf("%s(true): no change", k)
		}
		c2 := configFieldChanges(k, false)
		if c2 == nil {
			t.Fatalf("%s(false): no change", k)
		}
	}
	_ = utils.AppConfig{}
}
