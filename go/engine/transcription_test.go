package engine

import (
	"encoding/json"
	"strings"
	"sync"
	"testing"

	"uniclient/cores"
)

// transcribeStub: a core whose TranscribeAudio returns scripted results, and
// which records calls so tests can assert the RPC actually happened.
type transcribeStub struct {
	cores.StubCore
	mu     sync.Mutex
	calls  [][2]string // (chatID, msgID) pairs
	pend   bool
	text   string
	rpcErr error
}

func (s *transcribeStub) TranscribeAudio(chatID, msgID string) (bool, int64, string, error) {
	s.mu.Lock()
	s.calls = append(s.calls, [2]string{chatID, msgID})
	pend, text, err := s.pend, s.text, s.rpcErr
	s.mu.Unlock()
	return pend, 42, text, err
}

func (s *transcribeStub) lastCall() (string, string, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.calls) == 0 {
		return "", "", false
	}
	c := s.calls[len(s.calls)-1]
	return c[0], c[1], true
}

// seedVoiceMessage stores a cached voice message the way the cache layer
// does, so populateTranscriptions has a row to hydrate.
func seedVoiceMessage(t *testing.T, e *Engine, accountID, chatID, msgID string) {
	t.Helper()
	_, err := e.db.Exec(
		`INSERT OR REPLACE INTO messages
                 (account_id, chat_id, msg_id, sender_id, sender_name, content_text, timestamp, status, is_outgoing, has_media)
                 VALUES (?, ?, ?, 'u1', 'Alice', '', 1700000000, 1, 0, 1)`,
		accountID, chatID, msgID)
	if err != nil {
		t.Fatal(err)
	}
	_, err = e.db.Exec(
		`INSERT OR REPLACE INTO media (account_id, chat_id, msg_id, seq, media_type, mime_type, file_size, duration_ms)
                 VALUES (?, ?, ?, 0, ?, 'audio/ogg', 1234, 5000)`,
		accountID, chatID, msgID, MediaVoice)
	if err != nil {
		t.Fatal(err)
	}
}

// eventRecorder captures engine events for assertions.
type eventRecorder struct {
	mu     sync.Mutex
	events []EngineEvent
}

func (r *eventRecorder) record(data []byte) {
	var ev EngineEvent
	if err := json.Unmarshal(data, &ev); err != nil {
		return
	}
	r.mu.Lock()
	r.events = append(r.events, ev)
	r.mu.Unlock()
}

func (r *eventRecorder) count(typ string) int {
	r.mu.Lock()
	defer r.mu.Unlock()
	n := 0
	for _, ev := range r.events {
		if ev.Type == typ {
			n++
		}
	}
	return n
}

func (r *eventRecorder) last(typ string) (EngineEvent, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	for i := len(r.events) - 1; i >= 0; i-- {
		if r.events[i].Type == typ {
			return r.events[i], true
		}
	}
	return EngineEvent{}, false
}

func TestTranscriptionSupported(t *testing.T) {
	e := newTestEngine(t)
	e.accounts = map[string]*Account{
		"tg":  {ID: "tg", Core: &transcribeStub{}},
		"irc": {ID: "irc", Core: plainStub{}},
	}
	if !e.TranscriptionSupported("tg") {
		t.Error("transcriber core reported unsupported")
	}
	if e.TranscriptionSupported("irc") {
		t.Error("plain core reported transcription support")
	}
	if e.TranscriptionSupported("missing") {
		t.Error("missing account reported transcription support")
	}
}

func TestTranscribeVoiceNoteFinal(t *testing.T) {
	e := newTestEngine(t)
	stub := &transcribeStub{text: "hello world"}
	e.accounts = map[string]*Account{"tg": {ID: "tg", Core: stub}}

	text, pending, err := e.TranscribeVoiceNote("tg", "10", "500")
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if pending {
		t.Error("final transcription reported pending")
	}
	if text != "hello world" {
		t.Errorf("text = %q, want %q", text, "hello world")
	}
	if c, m, ok := stub.lastCall(); !ok || c != "10" || m != "500" {
		t.Errorf("core call = (%q,%q,%v), want (10,500,true)", c, m, ok)
	}

	// Stored: direct read-back.
	got, pend := e.GetCachedTranscription("tg", "10", "500")
	if got != "hello world" || pend {
		t.Errorf("GetCachedTranscription = (%q,%v)", got, pend)
	}
}

func TestTranscribeVoiceNotePendingRoundTrip(t *testing.T) {
	e := newTestEngine(t)
	stub := &transcribeStub{pend: true, text: ""}
	e.accounts = map[string]*Account{"tg": {ID: "tg", Core: stub}}

	text, pending, err := e.TranscribeVoiceNote("tg", "10", "501")
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if !pending {
		t.Error("pending transcription reported final")
	}
	if text != "" {
		t.Errorf("pending text = %q, want empty", text)
	}
	// The pending row is visible so the GUI can render "Transcribing…".
	got, pend := e.GetCachedTranscription("tg", "10", "501")
	if !pend {
		t.Error("cached row not pending")
	}
	if got != "" {
		t.Errorf("cached pending text = %q", got)
	}
}

func TestTranscribeVoiceNoteUnsupported(t *testing.T) {
	e := newTestEngine(t)
	e.accounts = map[string]*Account{"irc": {ID: "irc", Core: plainStub{}}}
	if _, _, err := e.TranscribeVoiceNote("irc", "10", "1"); err == nil {
		t.Error("unsupported core: want honest error, got nil")
	} else if !strings.Contains(err.Error(), "transcription") {
		t.Errorf("err = %v, want transcription mention", err)
	}
}

func TestTranscribeVoiceNoteCoreError(t *testing.T) {
	e := newTestEngine(t)
	stub := &transcribeStub{rpcErr: errFake("VOICE_MESSAGES_FORBIDDEN")}
	e.accounts = map[string]*Account{"tg": {ID: "tg", Core: stub}}
	if _, _, err := e.TranscribeVoiceNote("tg", "10", "502"); err == nil {
		t.Error("core error swallowed")
	}
	// No row may be written on failure.
	if text, _ := e.GetCachedTranscription("tg", "10", "502"); text != "" {
		t.Errorf("failed transcription stored text %q", text)
	}
}

func TestHandleUpdateTranscriptionFlipsPending(t *testing.T) {
	e := newTestEngine(t)
	rec := &eventRecorder{}
	e.SetEventCallback(rec.record)

	stub := &transcribeStub{pend: true}
	e.accounts = map[string]*Account{"tg": {ID: "tg", Core: stub}}

	if _, _, err := e.TranscribeVoiceNote("tg", "10", "503"); err != nil {
		t.Fatal(err)
	}
	if _, pend := e.GetCachedTranscription("tg", "10", "503"); !pend {
		t.Fatal("precondition: row should be pending")
	}

	// The server pushes updateTranscribedAudio with the final text.
	e.handleUpdate("tg", cores.Update{
		Type:   cores.UpdateTranscription,
		ChatID: "10",
		Transcription: &cores.TranscriptionUpdate{
			MessageID:       "503",
			TranscriptionID: 42,
			Pending:         false,
			Text:            "the quick brown fox",
		},
	})

	text, pend := e.GetCachedTranscription("tg", "10", "503")
	if pend {
		t.Error("row still pending after final update")
	}
	if text != "the quick brown fox" {
		t.Errorf("text = %q", text)
	}
	if rec.count(EventMsgTranscribed) != 1 {
		t.Errorf("EventMsgTranscribed emitted %d times, want 1", rec.count(EventMsgTranscribed))
	}
	if ev, ok := rec.last(EventMsgTranscribed); ok {
		var d MsgTranscribedEvent
		if err := json.Unmarshal([]byte(mustJSON(t, ev.Data)), &d); err != nil {
			t.Fatalf("event data decode: %v", err)
		}
		if d.ChatID != "10" || d.MsgID != "503" || d.Text != "the quick brown fox" || d.Pending {
			t.Errorf("event data = %+v", d)
		}
	}
}

func TestHandleUpdateTranscriptionUnknownMessageIgnored(t *testing.T) {
	e := newTestEngine(t)
	rec := &eventRecorder{}
	e.SetEventCallback(rec.record)

	// An update for a message nobody requested must not create a row (the
	// transcription is only interesting once the user asked for it — matches
	// Telegram: rows surface on explicit user action).
	e.handleUpdate("tg", cores.Update{
		Type:   cores.UpdateTranscription,
		ChatID: "10",
		Transcription: &cores.TranscriptionUpdate{
			MessageID: "999",
			Pending:   false,
			Text:      "unsolicited",
		},
	})
	if text, _ := e.GetCachedTranscription("tg", "10", "999"); text != "" {
		t.Errorf("unsolicited transcription stored: %q", text)
	}
	if rec.count(EventMsgTranscribed) != 0 {
		t.Error("event emitted for unknown message")
	}
}

func TestPopulateTranscriptionsHydratesVoiceMessages(t *testing.T) {
	e := newTestEngine(t)
	seedVoiceMessage(t, e, "tg", "10", "600")
	seedVoiceMessage(t, e, "tg", "10", "601")

	if _, serr := e.storeTranscription("tg", "10", "600", 7, "hello from store", false); serr != nil {
		t.Fatal(serr)
	}
	if _, serr := e.storeTranscription("tg", "10", "601", 8, "", true); serr != nil {
		t.Fatal(serr)
	}

	msgs, err := e.GetMessages("tg", "10", 0, 0, 50)
	if err != nil {
		t.Fatal(err)
	}
	byID := map[string]CachedMessage{}
	for _, m := range msgs {
		byID[m.MsgID] = m
	}
	m600 := byID["600"]
	if m600.TranscriptionText != "hello from store" || m600.TranscriptionPending {
		t.Errorf("600 transcription = (%q,%v)", m600.TranscriptionText, m600.TranscriptionPending)
	}
	m601 := byID["601"]
	if !m601.TranscriptionPending || m601.TranscriptionText != "" {
		t.Errorf("601 transcription = (%q,%v)", m601.TranscriptionText, m601.TranscriptionPending)
	}
}

func mustJSON(t *testing.T, v any) string {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

type errFake string

func (e errFake) Error() string { return string(e) }
