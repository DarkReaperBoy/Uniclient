package cores

import (
	"testing"

	"github.com/gotd/td/tg"
)

// wireBusinessFullUser builds a self userFull with every business field
// populated — the read-model source of truth for the tests below.
func wireBusinessFullUser() *tg.UserFull {
	full := &tg.UserFull{}
	wh := &tg.BusinessWorkHours{
		TimezoneID: "Europe/Berlin",
		OpenNow:    true,
		WeeklyOpen: []tg.BusinessWeeklyOpen{
			{StartMinute: 9 * 60, EndMinute: 17 * 60},                 // Mon 09:00–17:00
			{StartMinute: 1*24*60 + 9*60, EndMinute: 1*24*60 + 17*60}, // Tue
			{StartMinute: 6*24*60 + 21*60, EndMinute: 7*24*60 + 4*60}, // Sun 21:00 → Mon 04:00 (wrap)
		},
	}
	full.SetBusinessWorkHours(*wh)
	loc := &tg.BusinessLocation{Address: "Kastanienallee 1"}
	loc.SetGeoPoint(&tg.GeoPoint{Lat: 52.5295, Long: 13.3936})
	full.SetBusinessLocation(*loc)
	full.SetBusinessGreetingMessage(tg.BusinessGreetingMessage{
		ShortcutID:     3,
		NoActivityDays: 14,
		Recipients: tg.BusinessRecipients{
			NewChats:    true,
			NonContacts: true,
		},
	})
	full.SetBusinessAwayMessage(tg.BusinessAwayMessage{
		OfflineOnly: true,
		ShortcutID:  4,
		Schedule:    &tg.BusinessAwayMessageScheduleOutsideWorkHours{},
		Recipients: tg.BusinessRecipients{
			ExistingChats:   true,
			ExcludeSelected: false,
		},
	})
	full.SetBusinessIntro(tg.BusinessIntro{
		Title:       "Welcome!",
		Description: "We reply within a day.",
	})
	return full
}

func wireQuickReplies() []QuickReplyInfo {
	return []QuickReplyInfo{
		{ID: 3, Name: "greeting", Count: 1, TopMessage: "Hi there!"},
		{ID: 4, Name: "away", Count: 2, TopMessage: "We're away"},
		{ID: 9, Name: "prices", Count: 3, TopMessage: "See our prices"},
	}
}

// TestBusinessInfoFromWire: every business field of the self userFull
// lands in the read model, greeting/away texts resolve through the
// quick-reply list, and the schedule maps to its string discriminator.
func TestBusinessInfoFromWire(t *testing.T) {
	self := &tg.User{ID: 1, Self: true, Premium: true}
	out := businessInfoFromWire(wireBusinessFullUser(), self, wireQuickReplies())

	if v, _ := out["premium"].(bool); !v {
		t.Fatalf("premium = %v, want true", out["premium"])
	}
	wh, ok := out["work_hours"].(map[string]interface{})
	if !ok {
		t.Fatalf("work_hours missing: %v", out)
	}
	if wh["timezone_id"] != "Europe/Berlin" {
		t.Fatalf("timezone = %v", wh["timezone_id"])
	}
	if wh["open_now"] != true {
		t.Fatalf("open_now = %v", wh["open_now"])
	}
	ivs := wh["weekly_open"].([]map[string]interface{})
	if len(ivs) != 3 {
		t.Fatalf("intervals = %d, want 3", len(ivs))
	}
	if ivs[2]["end"] != 7*24*60+4*60 {
		t.Fatalf("wrap interval end = %v", ivs[2]["end"])
	}

	loc, ok := out["location"].(map[string]interface{})
	if !ok || loc["address"] != "Kastanienallee 1" {
		t.Fatalf("location = %v", out["location"])
	}
	if loc["lat"] != 52.5295 || loc["lon"] != 13.3936 {
		t.Fatalf("geo = %v/%v", loc["lat"], loc["lon"])
	}

	g, ok := out["greeting"].(map[string]interface{})
	if !ok {
		t.Fatalf("greeting missing")
	}
	if g["shortcut_id"] != 3 || g["no_activity_days"] != 14 {
		t.Fatalf("greeting ids = %v/%v", g["shortcut_id"], g["no_activity_days"])
	}
	if g["message"] != "Hi there!" {
		t.Fatalf("greeting message = %q", g["message"])
	}
	if g["new_chats"] != true || g["non_contacts"] != true {
		t.Fatalf("greeting recipients = %v", g)
	}
	if g["existing_chats"] != false {
		t.Fatalf("existing_chats leaked = %v", g["existing_chats"])
	}

	aw, ok := out["away"].(map[string]interface{})
	if !ok {
		t.Fatalf("away missing")
	}
	if aw["message"] != "We're away" || aw["schedule"] != "outside_work_hours" {
		t.Fatalf("away = %v", aw)
	}
	if aw["offline_only"] != true {
		t.Fatalf("offline_only = %v", aw["offline_only"])
	}

	intro, ok := out["intro"].(map[string]interface{})
	if !ok || intro["title"] != "Welcome!" {
		t.Fatalf("intro = %v", out["intro"])
	}
}

// TestBusinessInfoFromWireEmpty: a bare userFull yields an honest,
// near-empty model (no fabricated sections).
func TestBusinessInfoFromWireEmpty(t *testing.T) {
	out := businessInfoFromWire(&tg.UserFull{}, &tg.User{Self: true}, nil)
	if len(out) != 1 { // premium=false only
		t.Fatalf("model = %v", out)
	}
	if v, _ := out["premium"].(bool); v {
		t.Fatalf("premium should be false")
	}
}

// TestQuickRepliesFromWire: shortcut rows resolve their top message text
// from the messages vector.
func TestQuickRepliesFromWire(t *testing.T) {
	res := &tg.MessagesQuickReplies{
		QuickReplies: []tg.QuickReply{
			{ShortcutID: 3, Shortcut: "greeting", TopMessage: 101, Count: 1},
			{ShortcutID: 9, Shortcut: "prices", TopMessage: 202, Count: 3},
		},
		Messages: []tg.MessageClass{
			&tg.Message{ID: 101, Message: "Hi there!"},
			&tg.Message{ID: 202, Message: "See our prices"},
		},
	}
	rows := quickRepliesFromWire(res)
	if len(rows) != 2 {
		t.Fatalf("rows = %d", len(rows))
	}
	if rows[0].Name != "greeting" || rows[0].TopMessage != "Hi there!" || rows[0].Count != 1 {
		t.Fatalf("row0 = %+v", rows[0])
	}
	if rows[1].TopMessage != "See our prices" {
		t.Fatalf("row1 = %+v", rows[1])
	}
}

// TestTimezonesFromWire: id/name/offset carried through.
func TestTimezonesFromWire(t *testing.T) {
	res := &tg.HelpTimezonesList{Timezones: []tg.Timezone{
		{ID: "Europe/Berlin", Name: "Berlin", UtcOffset: 3600},
		{ID: "UTC", Name: "UTC", UtcOffset: 0},
	}}
	tzs := timezonesFromWire(res)
	if len(tzs) != 2 || tzs[0].ID != "Europe/Berlin" || tzs[0].UtcOffset != 3600 {
		t.Fatalf("tzs = %+v", tzs)
	}
}

// TestBuildWorkHours: interval mapping + validation + clear semantics.
func TestBuildWorkHours(t *testing.T) {
	// clear on empty
	if wh, err := buildWorkHours(map[string]interface{}{}); wh != nil || err != nil {
		t.Fatalf("empty → %v/%v", wh, err)
	}
	// valid schedule
	wh, err := buildWorkHours(map[string]interface{}{
		"timezone_id": "Europe/Berlin",
		"weekly_open": []interface{}{
			map[string]interface{}{"start": 540, "end": 1020},
			map[string]interface{}{"start": 6 * 24 * 60, "end": 7 * 24 * 60},
		},
	})
	if err != nil || wh == nil {
		t.Fatalf("build: %v", err)
	}
	if wh.TimezoneID != "Europe/Berlin" || len(wh.WeeklyOpen) != 2 {
		t.Fatalf("wh = %+v", wh)
	}
	if wh.WeeklyOpen[1].EndMinute != 10080 {
		t.Fatalf("end = %d", wh.WeeklyOpen[1].EndMinute)
	}
	// end beyond the 8*24*60 ceiling rejects
	_, err = buildWorkHours(map[string]interface{}{
		"weekly_open": []interface{}{map[string]interface{}{"start": 0, "end": 8*24*60 + 1}},
	})
	if err == nil {
		t.Fatalf("out-of-range end accepted")
	}
	// inverted interval rejects
	_, err = buildWorkHours(map[string]interface{}{
		"weekly_open": []interface{}{map[string]interface{}{"start": 600, "end": 540}},
	})
	if err == nil {
		t.Fatalf("inverted interval accepted")
	}
}

// TestBuildLocation: clear / address-only / address+geo / errors.
func TestBuildLocation(t *testing.T) {
	if a, g, err := buildLocation(map[string]interface{}{}); a != "" || g != nil || err != nil {
		t.Fatalf("empty → %q/%v/%v", a, g, err)
	}
	a, g, err := buildLocation(map[string]interface{}{"address": "  Main St 1 "})
	if err != nil || a != "Main St 1" || g != nil {
		t.Fatalf("address-only → %q/%v/%v", a, g, err)
	}
	a, g, err = buildLocation(map[string]interface{}{"address": "Main St 1", "lat": 52.5, "lon": 13.4})
	if err != nil || g == nil || g.Lat != 52.5 || g.Long != 13.4 {
		t.Fatalf("address+geo → %q/%+v/%v", a, g, err)
	}
	if _, _, err := buildLocation(map[string]interface{}{"lat": 52.5}); err == nil {
		t.Fatalf("geo without address accepted")
	}
}

// TestBuildGreeting: defaults, validation and clear.
func TestBuildGreeting(t *testing.T) {
	if m, err := buildGreeting(map[string]interface{}{}); m != nil || err != nil {
		t.Fatalf("empty → %v/%v", m, err)
	}
	m, err := buildGreeting(map[string]interface{}{
		"new_chats": true, "no_activity_days": 21, "shortcut_id": 3,
	})
	if err != nil || m == nil {
		t.Fatalf("build: %v", err)
	}
	if m.NoActivityDays != 21 || m.ShortcutID != 3 || !m.Recipients.NewChats {
		t.Fatalf("m = %+v", m)
	}
	// default inactivity = 7
	m, _ = buildGreeting(map[string]interface{}{"contacts": true})
	if m.NoActivityDays != 7 {
		t.Fatalf("default days = %d", m.NoActivityDays)
	}
	// invalid inactivity
	if _, err := buildGreeting(map[string]interface{}{"contacts": true, "no_activity_days": 10}); err == nil {
		t.Fatalf("days=10 accepted")
	}
	// no recipients
	if _, err := buildGreeting(map[string]interface{}{}); err != nil || true {
		// empty map clears before recipient validation
	}
	if _, err := buildGreeting(map[string]interface{}{"no_activity_days": 7}); err == nil {
		t.Fatalf("no recipients accepted")
	}
}

// TestBuildAway: the three schedule modes + custom validation.
func TestBuildAway(t *testing.T) {
	if m, err := buildAway(map[string]interface{}{}); m != nil || err != nil {
		t.Fatalf("empty → %v/%v", m, err)
	}
	m, err := buildAway(map[string]interface{}{"existing_chats": true})
	if err != nil || m == nil {
		t.Fatalf("build: %v", err)
	}
	if _, ok := m.Schedule.(*tg.BusinessAwayMessageScheduleAlways); !ok || !m.Recipients.ExistingChats {
		t.Fatalf("default schedule = %T", m.Schedule)
	}
	m, _ = buildAway(map[string]interface{}{"existing_chats": true, "schedule": "outside_work_hours"})
	if _, ok := m.Schedule.(*tg.BusinessAwayMessageScheduleOutsideWorkHours); !ok {
		t.Fatalf("outside schedule = %T", m.Schedule)
	}
	m, err = buildAway(map[string]interface{}{
		"existing_chats": true, "schedule": "custom",
		"start_date": 1737000000, "end_date": 1738000000,
	})
	if err != nil {
		t.Fatalf("custom: %v", err)
	}
	c, ok := m.Schedule.(*tg.BusinessAwayMessageScheduleCustom)
	if !ok || c.StartDate != 1737000000 {
		t.Fatalf("custom = %+v", m.Schedule)
	}
	if _, err := buildAway(map[string]interface{}{"existing_chats": true, "schedule": "custom"}); err == nil {
		t.Fatalf("custom without dates accepted")
	}
	if _, err := buildAway(map[string]interface{}{"existing_chats": true, "schedule": "bogus"}); err == nil {
		t.Fatalf("bogus schedule accepted")
	}
}

// TestBuildIntro: mandatory fields, clear, length caps.
func TestBuildIntro(t *testing.T) {
	if m, err := buildIntro(map[string]interface{}{}); m != nil || err != nil {
		t.Fatalf("empty → %v/%v", m, err)
	}
	if m, err := buildIntro(map[string]interface{}{"title": "  ", "description": "x"}); m != nil || err != nil {
		t.Fatalf("blank title should clear → %v/%v", m, err)
	}
	if _, err := buildIntro(map[string]interface{}{"title": "Hi", "description": ""}); err == nil {
		t.Fatalf("missing description accepted")
	}
	m, err := buildIntro(map[string]interface{}{"title": "Hi", "description": "We reply fast"})
	if err != nil || m.Title != "Hi" || m.Description != "We reply fast" {
		t.Fatalf("m = %+v err=%v", m, err)
	}
}

// TestSanitizeShortcutName: char whitelist, 12-char cap, fallback.
func TestSanitizeShortcutName(t *testing.T) {
	if got := sanitizeShortcutName("greeting", "x"); got != "greeting" {
		t.Fatalf("plain = %q", got)
	}
	if got := sanitizeShortcutName("my very long shortcut name!!", "x"); got != "myverylongsh" {
		t.Fatalf("long = %q", got)
	}
	if got := sanitizeShortcutName("héllo wörld", "fb"); got != "hllowrld" {
		t.Fatalf("non-ascii = %q, want stripped", got)
	}
	if got := sanitizeShortcutName("öö", "fb"); got != "fb" {
		t.Fatalf("all-invalid = %q, want fallback", got)
	}
	if got := sanitizeShortcutName("", "away"); got != "away" {
		t.Fatalf("empty = %q", got)
	}
}

// TestLenientDataReaders: the map readers accept int/float/string/bool.
func TestLenientDataReaders(t *testing.T) {
	m := map[string]interface{}{
		"b": true, "s": "str", "i": 7, "f": 1.5,
		"bs": "true", "is": "42", "fs": "2.5",
	}
	if !dataBool(m, "b") || !dataBool(m, "bs") {
		t.Fatalf("bool readers")
	}
	if dataStr(m, "s") != "str" || dataStr(nil, "s") != "" {
		t.Fatalf("str readers")
	}
	if dataInt(m, "i") != 7 || dataInt(m, "is") != 42 || dataInt(m, "f") != 1 {
		t.Fatalf("int readers")
	}
	if f, ok := dataFloat(m, "f"); !ok || f != 1.5 {
		t.Fatalf("float reader")
	}
	if f, ok := dataFloat(m, "fs"); !ok || f != 2.5 {
		t.Fatalf("string float reader")
	}
	if _, ok := dataFloat(m, "missing"); ok {
		t.Fatalf("missing key claimed present")
	}
}
