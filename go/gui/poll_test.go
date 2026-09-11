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

// ── slice 124: retract / multi-vote / stop / solution ─────────────────────

func pollMsg(extra string) *engine.CachedMessage {
	return &engine.CachedMessage{
		AccountID:  "acc",
		ChatID:     "chat",
		MsgID:      "42",
		IsOutgoing: true,
		ContentRaw: []byte(extra),
	}
}

func TestApplyPollOverlayRetract(t *testing.T) {
	d := &pollData{
		Question:    "Q",
		TotalVoters: 2,
		Options: []pollOption{
			{Text: "A", Voters: 2, Chosen: true},
			{Text: "B", Voters: 1},
		},
	}
	// Empty (non-nil) overlay = full retraction of my server-counted vote.
	applyPollOverlay(d, map[int]bool{})
	if d.Options[0].Chosen || d.Options[0].Voters != 1 {
		t.Errorf("retract did not remove own vote: %+v", d.Options[0])
	}
	if d.TotalVoters != 1 {
		t.Errorf("total = %d, want 1", d.TotalVoters)
	}
	// nil overlay = no opinion (server truth untouched).
	d2 := &pollData{TotalVoters: 5, Options: []pollOption{{Text: "A", Voters: 5, Chosen: true}}}
	applyPollOverlay(d2, nil)
	if !d2.Options[0].Chosen || d2.TotalVoters != 5 {
		t.Errorf("nil overlay must be a no-op: %+v", d2)
	}
}

func TestPollTapAction(t *testing.T) {
	open := &pollData{Options: []pollOption{{Text: "A"}, {Text: "B"}}}
	cases := []struct {
		name    string
		d       *pollData
		overlay map[int]bool
		idx     int
		want    string
	}{
		{"first vote single", open, nil, 0, "vote"},
		{"retract own choice", open, map[int]bool{0: true}, 0, "retract"},
		{"switch option blocked", open, map[int]bool{0: true}, 1, "none"},
		{"toggle adds", &pollData{Multiple: true, Options: []pollOption{{}, {}}}, map[int]bool{0: true}, 1, "toggle"},
		{"toggle removes", &pollData{Multiple: true, Options: []pollOption{{}, {}}}, map[int]bool{0: true}, 0, "toggle"},
		{"quiz locks after vote", &pollData{Quiz: true, Options: []pollOption{{}, {}}}, map[int]bool{1: true}, 0, "none"},
		{"quiz first vote ok", &pollData{Quiz: true, Options: []pollOption{{}, {}}}, nil, 0, "vote"},
		{"quiz server-voted lock", &pollData{Quiz: true, Options: []pollOption{{Text: "A", Chosen: true}, {}}}, nil, 1, "none"},
		{"closed poll", &pollData{Closed: true, Options: []pollOption{{}, {}}}, nil, 0, "none"},
		{"bad index", open, nil, 5, "none"},
		{"nil poll", nil, nil, 0, "none"},
		{"retract via server state", &pollData{Options: []pollOption{{Text: "A", Chosen: true}, {}}}, nil, 0, "retract"},
	}
	for _, c := range cases {
		if got := pollTapAction(c.d, c.overlay, c.idx); got != c.want {
			t.Errorf("%s: pollTapAction = %q, want %q", c.name, got, c.want)
		}
	}
}

func TestNextMultiVoteSet(t *testing.T) {
	if got := nextMultiVoteSet(nil, 2); len(got) != 1 || got[0] != 2 {
		t.Errorf("add to empty = %v, want [2]", got)
	}
	if got := nextMultiVoteSet(map[int]bool{0: true, 2: true}, 2); len(got) != 1 || got[0] != 0 {
		t.Errorf("remove existing = %v, want [0]", got)
	}
	if got := nextMultiVoteSet(map[int]bool{2: true, 0: true}, 1); len(got) != 3 {
		t.Errorf("add to set = %v, want 3 sorted entries", got)
	} else if got[0] != 0 || got[1] != 1 || got[2] != 2 {
		t.Errorf("sorted order violated: %v", got)
	}
}

func TestStopPollMenuGate(t *testing.T) {
	mk := func(outgoing bool, raw string) *engine.CachedMessage {
		m := pollMsg(raw)
		m.IsOutgoing = outgoing
		return m
	}
	open := `{"extra":{"poll_question":"Q","poll_options":[{"text":"a"},{"text":"b"}]}}`
	closed := `{"extra":{"poll_question":"Q","poll_closed":true,"poll_options":[{"text":"a"},{"text":"b"}]}}`
	if !stopPollMenuGate(mk(true, open)) {
		t.Error("own open poll must offer Stop poll")
	}
	if stopPollMenuGate(mk(false, open)) {
		t.Error("foreign poll must not offer Stop poll")
	}
	if stopPollMenuGate(mk(true, closed)) {
		t.Error("closed poll must not offer Stop poll")
	}
	if stopPollMenuGate(mk(true, `{"extra":{}}`)) {
		t.Error("non-poll message must not offer Stop poll")
	}
	if stopPollMenuGate(nil) {
		t.Error("nil message must not offer Stop poll")
	}
}

func TestPollEffectiveClosed(t *testing.T) {
	if !pollEffectiveClosed(&pollData{Closed: true}, false) {
		t.Error("server-closed poll not closed")
	}
	if !pollEffectiveClosed(&pollData{}, true) {
		t.Error("optimistic stop not applied")
	}
	if pollEffectiveClosed(&pollData{}, false) {
		t.Error("open poll reported closed")
	}
	if pollEffectiveClosed(nil, true) {
		t.Error("nil poll reported closed")
	}
}

func TestParsePollSolution(t *testing.T) {
	m := pollMsg(`{"extra":{"poll_question":"1+1?","poll_quiz":true,"poll_solution":"because math","poll_options":[{"text":"2","correct":true},{"text":"3"}]}}`)
	d := parsePollMessage(m)
	if d == nil || d.Solution != "because math" {
		t.Fatalf("solution not parsed: %+v", d)
	}
	if !d.Options[0].Correct {
		t.Error("correct flag not parsed")
	}
}
