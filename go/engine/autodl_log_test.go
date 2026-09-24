package engine

// tests-first for BUGS.md B-7 — auto-download RequestDownload errors
// must not be silent.
//
// maybeAutoDownload fired `e.RequestDownload(...)` with the result
// thrown away: correct for ErrStreamActive (playback is already saving
// the file), but every OTHER error — missing media row, uninitialized
// media manager, … — vanished without a trace, so a broken
// auto-download pipeline was indistinguishable from "settings said
// no".

import (
	"bytes"
	"log"
	"os"
	"strings"
	"testing"

	"uniclient/cores"
)

// seedAutoDLChat creates the account (FK) + a DM chat row so the
// auto-download source resolves to "private".
func seedAutoDLChat(t *testing.T, e *Engine) {
	t.Helper()
	if _, err := e.db.Exec(
		`INSERT INTO accounts (id, platform, created_at) VALUES ('a1','telegram',0)`); err != nil {
		t.Fatal(err)
	}
	if _, err := e.db.Exec(
		`INSERT INTO chats (account_id, chat_id, type, title, updated_at) VALUES ('a1','c1',?,'Alice',0)`,
		ChatTypeDMVal); err != nil {
		t.Fatal(err)
	}
}

// autoDLMsg: one small photo attachment (default rules download photos
// under 10 MB).
func autoDLMsg() *cores.Message {
	return &cores.Message{
		ID:          "m1",
		Attachments: []cores.FileRef{{ID: "REF-1", Name: "x.jpg", MimeType: "image/jpeg", Size: 1000}},
	}
}

func TestAutoDownloadLogsUnexpectedRequestErrors(t *testing.T) {
	e := newTestEngine(t)
	seedAutoDLChat(t, e)
	e.media = &MediaManager{} // gate only: the error fires before any enqueue

	var buf bytes.Buffer
	log.SetOutput(&buf)
	defer log.SetOutput(os.Stderr)

	e.maybeAutoDownload("a1", "c1", autoDLMsg())

	out := buf.String()
	if !strings.Contains(out, "auto-download") || !strings.Contains(out, "media ref not found") {
		t.Fatalf("unexpected auto-download error was silent (B-7); log = %q", out)
	}
}

// TestAutoDownloadStaysQuietOnStreamActive pins the benign exception:
// the stream is already persisting these bytes, so a log line per
// attachment would be noise.
func TestAutoDownloadStaysQuietOnStreamActive(t *testing.T) {
	e := newTestEngine(t)
	seedAutoDLChat(t, e)
	seedStreamRow(t, e, 4096, 0, "") // media row exists (incomplete, no file)
	e.media = &MediaManager{}
	if !e.claimStream(mediaGuardKey("a1", "c1", "m1", 0)) {
		t.Fatal("claimStream failed on a fresh guard")
	}

	var buf bytes.Buffer
	log.SetOutput(&buf)
	defer log.SetOutput(os.Stderr)

	e.maybeAutoDownload("a1", "c1", autoDLMsg())

	if out := buf.String(); out != "" {
		t.Fatalf("ErrStreamActive must stay quiet (the stream is saving the file), got log %q", out)
	}
}
