package tests

import (
	"bytes"
	"log"
	"os"
	"strings"
	"testing"
	. "uniclient/engine"

	"uniclient/cores"
)

func seedAutoDLChat(t *testing.T, e *dbEngine) {
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

func autoDLMsg() *cores.Message {
	return &cores.Message{
		ID:          "m1",
		Attachments: []cores.FileRef{{ID: "REF-1", Name: "x.jpg", MimeType: "image/jpeg", Size: 1000}},
	}
}

func TestAutoDownloadLogsUnexpectedRequestErrors(t *testing.T) {
	e := newTestEngine(t)
	seedAutoDLChat(t, e)
	if err := e.UseMediaDir(t.TempDir()); err != nil {
		t.Fatal(err)
	}

	var buf bytes.Buffer
	log.SetOutput(&buf)
	defer log.SetOutput(os.Stderr)

	e.MaybeAutoDownload("a1", "c1", autoDLMsg())

	out := buf.String()
	if !strings.Contains(out, "auto-download") || !strings.Contains(out, "media ref not found") {
		t.Fatalf("unexpected auto-download error was silent (B-7); log = %q", out)
	}
}

func TestAutoDownloadStaysQuietOnStreamActive(t *testing.T) {
	e := newTestEngine(t)
	seedAutoDLChat(t, e)
	seedStreamRow(t, e, 4096, 0, "")
	if err := e.UseMediaDir(t.TempDir()); err != nil {
		t.Fatal(err)
	}
	if !e.ClaimStream(MediaGuardKey("a1", "c1", "m1", 0)) {
		t.Fatal("claimStream failed on a fresh guard")
	}

	var buf bytes.Buffer
	log.SetOutput(&buf)
	defer log.SetOutput(os.Stderr)

	e.MaybeAutoDownload("a1", "c1", autoDLMsg())

	if out := buf.String(); out != "" {
		t.Fatalf("ErrStreamActive must stay quiet (the stream is saving the file), got log %q", out)
	}
}
