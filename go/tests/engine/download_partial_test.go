package tests

import (
	"errors"
	"os"
	"path/filepath"
	"testing"

	. "uniclient/engine"
)

func TestExecuteDownloadRemovesPartialOnFailure(t *testing.T) {
	e, core, _ := newGuardEngine(t)

	core.dlErr = errors.New("simulated transfer failure")

	rec := &evRecorder{}
	sub := e.Subscribe(rec.record)
	defer sub.Unsubscribe()

	if err := e.RequestDownload("a1", "c1", "m1", 0, 0); err != nil {
		t.Fatalf("RequestDownload: %v", err)
	}
	waitUntil(t, "download_failed event", func() bool { return rec.has(EventDownloadFailed) })

	dir := filepath.Join(e.MediaDir(), "a1", "full")
	entries, err := os.ReadDir(dir)
	if err == nil {
		for _, entry := range entries {
			t.Errorf("failed download left a partial file: %s", entry.Name())
		}
	}

	var st int
	if err := e.db.QueryRow(
		`SELECT download_state FROM media WHERE account_id='a1' AND chat_id='c1' AND msg_id='m1' AND seq=0`).
		Scan(&st); err != nil {
		t.Fatal(err)
	}
	if st != DownloadFailed {
		t.Errorf("download_state = %d, want DownloadFailed(%d)", st, DownloadFailed)
	}
}
