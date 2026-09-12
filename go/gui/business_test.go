package gui

import (
	"strings"
	"testing"
)

// TestBizWeekFromWire: wire intervals (minute-of-week, cross-midnight
// friendly) split into per-day intervals; a piece crossing midnight
// lands its tail on the following day.
func TestBizWeekFromWire(t *testing.T) {
	w := bizWeekFromWire([]interface{}{
		map[string]interface{}{"start": 540, "end": 1020},              // Mon 09:00–17:00
		map[string]interface{}{"start": 1440 + 540, "end": 1440 + 660}, // Tue 09:00–11:00
	})
	if got := w[0]; len(got) != 1 || got[0].start != 540 || got[0].end != 1020 {
		t.Fatalf("Mon = %v", got)
	}
	if got := w[1]; len(got) != 1 || got[0].start != 540 || got[0].end != 660 {
		t.Fatalf("Tue = %v", got)
	}
	for d := 2; d < 7; d++ {
		if len(w[d]) != 0 {
			t.Fatalf("day %d should be closed: %v", d, w[d])
		}
	}
}

// TestBizWeekFromWireCrossMidnight: Sunday 21:00 → Monday 04:00 splits
// into Sun 21:00–24:00 and Mon 00:00–04:00.
func TestBizWeekFromWireCrossMidnight(t *testing.T) {
	w := bizWeekFromWire([]interface{}{
		map[string]interface{}{"start": 6*1440 + 21*60, "end": 7*1440 + 4*60},
	})
	if got := w[6]; len(got) != 1 || got[0].start != 21*60 || got[0].end != 1440 {
		t.Fatalf("Sun = %v", got)
	}
	if got := w[0]; len(got) != 1 || got[0].start != 0 || got[0].end != 4*60 {
		t.Fatalf("Mon = %v", got)
	}
}

// TestBizWeekFromWireMerges: overlapping/adjacent intervals within a day
// normalize to one.
func TestBizWeekFromWireMerges(t *testing.T) {
	w := bizWeekFromWire([]interface{}{
		map[string]interface{}{"start": 540, "end": 720},
		map[string]interface{}{"start": 720, "end": 1020},
		map[string]interface{}{"start": 600, "end": 660}, // inside
	})
	if got := w[0]; len(got) != 1 || got[0].start != 540 || got[0].end != 1020 {
		t.Fatalf("merged = %v", got)
	}
}

// TestBizWeekToWireRoundTrip: model → wire → model is lossless for
// simple (non-wrapping) schedules.
func TestBizWeekToWireRoundTrip(t *testing.T) {
	var w bizWeek
	w[0] = []bizIVL{{start: 540, end: 1020}}
	w[4] = []bizIVL{{start: 600, end: 720}, {start: 780, end: 900}}
	wire := w.toWire()
	w2 := bizWeekFromWire(wire)
	if len(w2[0]) != 1 || w2[0][0].start != 540 || w2[0][0].end != 1020 {
		t.Fatalf("Mon = %v", w2[0])
	}
	if len(w2[4]) != 2 || w2[4][1].start != 780 || w2[4][1].end != 900 {
		t.Fatalf("Fri = %v", w2[4])
	}
	if len(wire) != 3 {
		t.Fatalf("wire = %v", wire)
	}
}

// TestBizWeek247: the around-the-clock detection + setter.
func TestBizWeek247(t *testing.T) {
	var w bizWeek
	if !w.empty() || w.is247() {
		t.Fatalf("zero week: empty=%v 247=%v", w.empty(), w.is247())
	}
	w.set247()
	if !w.is247() || w.empty() {
		t.Fatalf("after set247: empty=%v 247=%v", w.empty(), w.is247())
	}
	// the single-interval 0..10080 wire form also reads back as 24/7
	w2 := bizWeekFromWire([]interface{}{map[string]interface{}{"start": 0, "end": 10080}})
	if !w2.is247() {
		t.Fatalf("wire 24/7 not detected: %v", w2)
	}
}

// TestBizWeekSummary: human schedule text collapses day ranges.
func TestBizWeekSummary(t *testing.T) {
	var w bizWeek
	if w.summary() != "" {
		t.Fatalf("empty summary = %q", w.summary())
	}
	for d := 0; d < 5; d++ {
		w[d] = []bizIVL{{start: 540, end: 1020}}
	}
	w.set247()
	if w.summary() != "24/7" {
		t.Fatalf("24/7 summary = %q", w.summary())
	}

	var x bizWeek
	for d := 0; d < 5; d++ {
		x[d] = []bizIVL{{start: 540, end: 1020}}
	}
	x[5] = []bizIVL{{start: 600, end: 840}}
	if got := x.summary(); got != "Mon–Fri 09:00–17:00, Sat 10:00–14:00" {
		t.Fatalf("summary = %q", got)
	}
}

// TestBizParseTime: lenient time parsing.
func TestBizParseTime(t *testing.T) {
	cases := []struct {
		in   string
		want int
		ok   bool
	}{
		{"9", 540, true},
		{"9:00", 540, true},
		{"09:30", 570, true},
		{"9.30", 570, true},
		{"17:00", 1020, true},
		{"24:00", 1440, true},
		{"", 0, false},
		{"25:00", 0, false},
		{"9:60", 0, false},
		{"24:30", 0, false},
		{"abc", 0, false},
	}
	for _, c := range cases {
		got, ok := bizParseTime(c.in)
		if ok != c.ok || (ok && got != c.want) {
			t.Fatalf("parse(%q) = %d,%v want %d,%v", c.in, got, ok, c.want, c.ok)
		}
	}
}

// TestBizFormatTime: zero-padded rendering.
func TestBizFormatTime(t *testing.T) {
	if bizFormatTime(540) != "09:00" || bizFormatTime(870) != "14:30" || bizFormatTime(1440) != "24:00" {
		t.Fatalf("format = %q %q %q", bizFormatTime(540), bizFormatTime(870), bizFormatTime(1440))
	}
}

// TestBizRecipientsRoundTrip: map → model → map is lossless.
func TestBizRecipientsRoundTrip(t *testing.T) {
	var r bizRecipients
	r.fromMap(map[string]interface{}{
		"new_chats":    true,
		"non_contacts": true,
	})
	m := r.toMap()
	if m["new_chats"] != true || m["non_contacts"] != true || m["existing_chats"] != false {
		t.Fatalf("m = %v", m)
	}
	var r2 bizRecipients
	r2.fromMap(m)
	if !r2.newChats || !r2.nonContacts || r2.existing || r2.contacts || r2.exclude {
		t.Fatalf("r2 = %+v", r2)
	}
}

// TestBizUtcLabel: offset rendering.
func TestBizUtcLabel(t *testing.T) {
	if bizUtcLabel(3600) != "UTC+01:00" {
		t.Fatalf("bizUtcLabel(3600) = %q", bizUtcLabel(3600))
	}
	if bizUtcLabel(-19800) != "UTC-05:30" {
		t.Fatalf("bizUtcLabel(-19800) = %q", bizUtcLabel(-19800))
	}
}

// TestBizSubMap: nested map digging.
func TestBizSubMap(t *testing.T) {
	info := map[string]interface{}{
		"greeting": map[string]interface{}{"message": "hi"},
	}
	if m := bizSubMap(info, "greeting"); m == nil || m["message"] != "hi" {
		t.Fatalf("greeting = %v", m)
	}
	if m := bizSubMap(info, "away"); m != nil {
		t.Fatalf("away = %v", m)
	}
	if m := bizSubMap(nil, "x"); m != nil {
		t.Fatalf("nil = %v", m)
	}
}

// TestBizSectionSubs: the honest subtitle helpers.
func TestBizSectionSubs(t *testing.T) {
	if got := bizLocationSub(nil); got != "Not set" {
		t.Fatalf("location sub = %q", got)
	}
	if got := bizGreetingSub(nil); got != "Off" {
		t.Fatalf("greeting sub = %q", got)
	}
	if got := bizAwaySub(nil); got != "Off" {
		t.Fatalf("away sub = %q", got)
	}
	if got := bizIntroSub(nil); got != "Not set" {
		t.Fatalf("intro sub = %q", got)
	}
	if got := bizRepliesSub(nil); got != "No shortcuts" {
		t.Fatalf("replies sub = %q", got)
	}
	info := map[string]interface{}{
		"location": map[string]interface{}{"address": "Main St 1"},
		"greeting": map[string]interface{}{"message": "Hello!"},
	}
	if bizLocationSub(info) != "Main St 1" || bizGreetingSub(info) != "Hello!" {
		t.Fatalf("subs = %q / %q", bizLocationSub(info), bizGreetingSub(info))
	}
	// away with schedule decoration
	awInfo := map[string]interface{}{
		"away": map[string]interface{}{"message": "Bye", "schedule": "outside_work_hours"},
	}
	if got := bizAwaySub(awInfo); !strings.Contains(got, "outside hours") {
		t.Fatalf("away sub = %q", got)
	}
}

// TestParseBizDate: "YYYY-MM-DD" → unix seconds.
func TestParseBizDate(t *testing.T) {
	s, ok := parseBizDate("2026-09-12")
	if !ok || s <= 0 {
		t.Fatalf("parse date = %d %v", s, ok)
	}
	if _, ok := parseBizDate("12.09.2026"); ok {
		t.Fatalf("european format accepted")
	}
	if _, ok := parseBizDate(""); ok {
		t.Fatalf("empty accepted")
	}
}
