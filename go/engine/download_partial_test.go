package engine

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

// TestExecuteDownloadRemovesPartialOnFailure (F-78): a core that wrote
// bytes to dest and THEN failed must not leave the truncated file —
// executeDownload's error branch marked the row DownloadFailed but
// kept the partial on disk, where any existence check (or the next
// reader that trusts the path) treats it as present content.
//
// Seam-RED (WORKLOG 314): undefined: guardCore.dlErr.
func TestExecuteDownloadRemovesPartialOnFailure(t *testing.T) {
	e, core, _ := newGuardEngine(t)

	core.dlErr = errors.New("simulated transfer failure")

	job := &downloadJob{
		AccountID: "a1", ChatID: "c1", MsgID: "m1", Seq: 0,
		RemoteRef: "REF-1", FileName: "clip.mp4", MimeType: "video/mp4", Extra: "777:Zm9v",
	}
	e.media.executeDownload(job)

	dir := filepath.Join(e.mediaDir, "a1", "full")
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
