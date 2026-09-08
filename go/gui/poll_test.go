package gui

import (
	"encoding/json"
	"testing"

	"uniclient/engine"
)

// Poll data rides in the cached message's raw JSON (cores.Message.Extra,
// filled by the telegram core's MessageMediaPoll conversion).
func pollRawMessage(t *testing.T, extra map[string]interface{}) []byte {
	t.Helper()
	type rawMsg struct {
		ID    string                 `json:"id"`
		Text  string                 `json:"text"`
		Extra map[string]interface{} `json:"extra,omitempty"`
	}
	b, err := json.Marshal(rawMsg{ID: "5", Text: "📊 Q", Extra: extra})
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	return b
}

func pollExtra(opts []map[string]interface{}, total float64) map[string]interface{} {
	return map[string]interface{}{
		"poll_question":     "Lunch?",
		"poll_quiz":         false,
		"poll_multiple":     false,
		"poll_public":       false,
		"poll_total_voters": total,
		"poll_options":      opts,
	}
}

func TestParsePollMessage(t *testing.T) {
	extra := pollExtra([]map[string]interface{}{
		{"text": "Pizza", "voters": float64(3), "chosen": true},
		{"text": "Sushi", "voters": float64(1)},
	}, 4)
	extra["poll_quiz"] = true
	extra["poll_public"] = true
	m := &engine.CachedMessage{AccountID: "a", ChatID: "c", MsgID: "5", ContentRaw: pollRawMessage(t, extra)}

	d := parsePollMessage(m)
	if d == nil {
		t.Fatal("expected poll data")
	}
	if d.Question != "Lunch?" {
		t.Errorf("question = %q", d.Question)
	}
	if !d.Quiz || !d.Public {
		t.Errorf("quiz/public flags = %v/%v", d.Quiz, d.Public)
	}
	if d.TotalVoters != 4 {
		t.Errorf("total voters = %d", d.TotalVoters)
	}
	if len(d.Options) != 2 {
		t.Fatalf("options = %d", len(d.Options))
	}
	if d.Options[0].Text != "Pizza" || d.Options[0].Voters != 3 || !d.Options[0].Chosen {
		t.Errorf("option 0 = %+v", d.Options[0])
	}
	if d.Options[1].Text != "Sushi" || d.Options[1].Voters != 1 || d.Options[1].Chosen {
		t.Errorf("option 1 = %+v", d.Options[1])
	}
}

func TestParsePollMessageRejectsNonPoll(t *testing.T) {
	cases := []struct {
		name string
		m    *engine.CachedMessage
	}{
		{"nil message", nil},
		{"no raw", &engine.CachedMessage{MsgID: "1"}},
		{"plain text", &engine.CachedMessage{MsgID: "1", ContentRaw: []byte(`{"id":"1","text":"hello"}`)}},
		{"empty question", &engine.CachedMessage{MsgID: "1", ContentRaw: pollRawMessage(t, pollExtra(nil, 0))}},
		{"single option", &engine.CachedMessage{MsgID: "1", ContentRaw: pollRawMessage(t, pollExtra([]map[string]interface{}{{"text": "only"}}, 0))}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if d := parsePollMessage(tc.m); d != nil {
				t.Errorf("expected nil for %s, got %+v", tc.name, d)
			}
		})
	}
}

func TestApplyPollOverlay(t *testing.T) {
	d := &pollData{
		Question:    "Q",
		TotalVoters: 2,
		Options: []pollOption{
			{Text: "A", Voters: 2, Chosen: true}, // server already counted me
			{Text: "B", Voters: 0},               // my new vote
			{Text: "C"},
		},
	}
	applyPollOverlay(d, map[int]bool{0: true, 1: true})
	if d.TotalVoters != 3 {
		t.Errorf("total = %d, want 3 (only the un-counted vote)", d.TotalVoters)
	}
	if d.Options[0].Voters != 2 || !d.Options[0].Chosen {
		t.Errorf("counted option must not double: %+v", d.Options[0])
	}
	if d.Options[1].Voters != 1 || !d.Options[1].Chosen {
		t.Errorf("overlay vote missing: %+v", d.Options[1])
	}
}

func TestPollPercent(t *testing.T) {
	cases := []struct {
		v, tot, want int
	}{
		{0, 0, 0}, {1, 0, 0}, {0, 4, 0}, {1, 4, 25}, {3, 4, 75}, {4, 4, 100}, {5, 4, 100},
	}
	for _, c := range cases {
		if got := pollPercent(c.v, c.tot); got != c.want {
			t.Errorf("pollPercent(%d,%d) = %d, want %d", c.v, c.tot, got, c.want)
		}
	}
}

func TestPollSubtitleAndFooter(t *testing.T) {
	if s := pollSubtitle(&pollData{Quiz: true}); s != "Quiz" {
		t.Errorf("quiz subtitle = %q", s)
	}
	if s := pollSubtitle(&pollData{Public: true}); s != "Public poll" {
		t.Errorf("public subtitle = %q", s)
	}
	if s := pollSubtitle(&pollData{}); s != "Anonymous poll" {
		t.Errorf("anon subtitle = %q", s)
	}
	if s := pollFooterLabel(&pollData{}); s != "No votes yet" {
		t.Errorf("empty footer = %q", s)
	}
	if s := pollFooterLabel(&pollData{TotalVoters: 1}); s != "1 vote" {
		t.Errorf("1 footer = %q", s)
	}
	if s := pollFooterLabel(&pollData{TotalVoters: 7}); s != "7 votes" {
		t.Errorf("7 footer = %q", s)
	}
	if s := pollFooterLabel(&pollData{Closed: true}); s != "No votes · closed" {
		t.Errorf("closed footer = %q", s)
	}
}

func TestValidatePollDraft(t *testing.T) {
	cases := []struct {
		q    string
		opts []string
		want string
	}{
		{"", []string{"a", "b"}, "Add a question"},
		{"  ", []string{"a", "b"}, "Add a question"},
		{"Q", []string{"a"}, "Add at least 2 options"},
		{"Q", []string{"a", " "}, "Add at least 2 options"},
		{"Q", []string{"a", "b"}, ""},
		{"Q", []string{"a", "b", "c"}, ""},
	}
	for _, c := range cases {
		if got := validatePollDraft(c.q, c.opts); got != c.want {
			t.Errorf("validatePollDraft(%q,%v) = %q, want %q", c.q, c.opts, got, c.want)
		}
	}
}
