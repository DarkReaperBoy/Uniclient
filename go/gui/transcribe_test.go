package gui

import (
	"testing"

	"uniclient/engine"
)

// Voice-note transcription (slice 115) — pure decision logic: glyph
// visibility, pending/final text routing, collapse depth. The engine-side
// store/update/event chain is pinned in engine/transcription_test.go.

func voiceMsg() *engine.CachedMessage {
	return &engine.CachedMessage{
		AccountID: "a",
		ChatID:    "c",
		MsgID:     "1",
		MediaType: engine.MediaVoice,
		HasMedia:  true,
	}
}

func TestTranscribeWanted(t *testing.T) {
	m := voiceMsg()

	// Capability gate first: no core support → no button.
	if transcribeWanted(m, false) {
		t.Fatal("glyph must hide without core support")
	}
	if !transcribeWanted(m, true) {
		t.Fatal("glyph must show for an untranscribed voice message")
	}

	// Non-voice media → hidden.
	photo := voiceMsg()
	photo.MediaType = engine.MediaImage
	if transcribeWanted(photo, true) {
		t.Fatal("glyph must hide for non-voice media")
	}

	// Already transcribed → the text block takes over.
	done := voiceMsg()
	done.TranscriptionText = "hello"
	if transcribeWanted(done, true) {
		t.Fatal("glyph must hide when text exists")
	}

	// Pending (in flight) → hidden too.
	pend := voiceMsg()
	pend.TranscriptionPending = true
	if transcribeWanted(pend, true) {
		t.Fatal("glyph must hide while pending")
	}

	// Nil safety.
	if transcribeWanted(nil, true) {
		t.Fatal("nil message must not show the glyph")
	}
}

func TestTranscriptLabelText(t *testing.T) {
	if transcriptLabelText(nil) != "" {
		t.Fatal("nil message must render no text")
	}
	pend := voiceMsg()
	pend.TranscriptionPending = true
	if got := transcriptLabelText(pend); got != "Transcribing…" {
		t.Fatalf("pending text = %q", got)
	}
	// Partial text while pending renders the partial (server pushed a draft).
	pend.TranscriptionText = "partial draf"
	if got := transcriptLabelText(pend); got != "partial draf" {
		t.Fatalf("pending partial = %q", got)
	}
	final := voiceMsg()
	final.TranscriptionText = "the final words"
	if got := transcriptLabelText(final); got != "the final words" {
		t.Fatalf("final text = %q", got)
	}
	// No transcription at all → no block.
	if got := transcriptLabelText(voiceMsg()); got != "" {
		t.Fatalf("unrequested text = %q", got)
	}
}

func TestTranscriptMaxLines(t *testing.T) {
	if transcriptMaxLines(true, false) != 1 {
		t.Fatal("pending must clamp to one line")
	}
	if transcriptMaxLines(true, true) != 1 {
		t.Fatal("expanded state cannot unclamp a pending hint")
	}
	if transcriptMaxLines(false, false) != 3 {
		t.Fatal("final collapsed text clamps to 3 lines")
	}
	if transcriptMaxLines(false, true) != 0 {
		t.Fatal("expanded text must be unlimited")
	}
}

func TestTranscriptClickablesStable(t *testing.T) {
	m1 := voiceMsg()
	m2 := voiceMsg()
	m2.MsgID = "2"
	a := &App{}
	a.wid.init()
	k1, k2 := transcriptKey(m1), transcriptKey(m2)
	if k1 == k2 {
		t.Fatal("different messages must key differently")
	}
	if a.transcribeClickable(k1) != a.transcribeClickable(k1) {
		t.Fatal("clickable must be stable per message")
	}
	if a.transcribeClickable(k1) == a.transcribeClickable(k2) {
		t.Fatal("different messages must get different clickables")
	}
	if a.transcriptExpandClickable(k1) != a.transcriptExpandClickable(k1) {
		t.Fatal("expand clickable must be stable per message")
	}
}

func TestTranscribeCapFor(t *testing.T) {
	a := &App{}
	if a.transcribeCapFor(nil) {
		t.Fatal("closed chat must report no capability")
	}
	if a.transcribeCapFor(&chatKey{AccountID: "x"}) {
		t.Fatal("unknown account must report no capability")
	}
	a.transcribeCap = map[string]bool{"tg": true}
	if !a.transcribeCapFor(&chatKey{AccountID: "tg"}) {
		t.Fatal("cached capability must be honored")
	}
}
