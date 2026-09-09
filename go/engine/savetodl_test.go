package engine

// Save-to-Downloads (slice 99, matrix row 158): copying a downloaded
// message media file into the user's downloads directory with a
// collision-safe name, and the honest not-downloaded sentinel.

import (
	"database/sql"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func seedMediaRow(t *testing.T, e *Engine, msgID, localPath, fileName string) {
	t.Helper()
	_, err := e.db.Exec(
		`INSERT INTO media (account_id, chat_id, msg_id, seq, media_type, local_path, file_name, download_state)
                 VALUES ('a1', 'c1', ?, 0, 8, ?, ?, 2)`,
		msgID, localPath, fileName)
	if err != nil {
		t.Fatal(err)
	}
}

func writeTempFile(t *testing.T, dir, name, content string) string {
	t.Helper()
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestSaveMessageMediaToDownloadsCopiesFile(t *testing.T) {
	e := newTestEngine(t)
	srcDir := t.TempDir()
	dlDir := t.TempDir()
	e.downloadDir = dlDir

	src := writeTempFile(t, srcDir, "cache.bin", "hello media")
	seedMediaRow(t, e, "m1", src, "report.pdf")

	dest, err := e.SaveMessageMediaToDownloads("a1", "c1", "m1", 0)
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Dir(dest) != dlDir {
		t.Fatalf("dest dir = %q, want %q", filepath.Dir(dest), dlDir)
	}
	if filepath.Base(dest) != "report.pdf" {
		t.Fatalf("dest name = %q, want report.pdf", filepath.Base(dest))
	}
	b, err := os.ReadFile(dest)
	if err != nil {
		t.Fatal(err)
	}
	if string(b) != "hello media" {
		t.Fatalf("dest content = %q, want %q", b, "hello media")
	}
	// The cache copy is untouched (save is a copy, never a move).
	if _, err := os.Stat(src); err != nil {
		t.Fatalf("cache copy vanished: %v", err)
	}
}

func TestSaveMessageMediaDedupNeverOverwrites(t *testing.T) {
	e := newTestEngine(t)
	srcDir := t.TempDir()
	dlDir := t.TempDir()
	e.downloadDir = dlDir

	src := writeTempFile(t, srcDir, "cache.bin", "first")
	seedMediaRow(t, e, "m1", src, "same.png")

	d1, err := e.SaveMessageMediaToDownloads("a1", "c1", "m1", 0)
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Base(d1) != "same.png" {
		t.Fatalf("first save name = %q, want same.png", filepath.Base(d1))
	}
	// A different file already sits at same.png in Downloads — the second
	// save must not clobber it.
	if err := os.WriteFile(filepath.Join(dlDir, "same.png"), []byte("precious"), 0o644); err != nil {
		t.Fatal(err)
	}
	d2, err := e.SaveMessageMediaToDownloads("a1", "c1", "m1", 0)
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Base(d2) == "same.png" {
		t.Fatal("second save overwrote the existing downloads file")
	}
	b, _ := os.ReadFile(filepath.Join(dlDir, "same.png"))
	if string(b) != "precious" {
		t.Fatalf("existing file was overwritten (content = %q)", b)
	}
}

func TestSaveMessageMediaNotDownloadedSentinel(t *testing.T) {
	e := newTestEngine(t)
	e.downloadDir = t.TempDir()
	seedMediaRow(t, e, "m2", "", "doc.pdf")

	_, err := e.SaveMessageMediaToDownloads("a1", "c1", "m2", 0)
	if !errors.Is(err, ErrMediaNotDownloaded) {
		t.Fatalf("err = %v, want ErrMediaNotDownloaded", err)
	}
}

func TestSaveMessageMediaMissingRow(t *testing.T) {
	e := newTestEngine(t)
	e.downloadDir = t.TempDir()
	if _, err := e.SaveMessageMediaToDownloads("a1", "c1", "nope", 0); err == nil {
		t.Fatal("missing media row must error")
	}
}

func TestSaveMessageMediaFileNameFallbacks(t *testing.T) {
	e := newTestEngine(t)
	srcDir := t.TempDir()
	dlDir := t.TempDir()
	e.downloadDir = dlDir

	// Empty stored file_name: derive from the cache path.
	src := writeTempFile(t, srcDir, "9f2c.jpg", "img")
	seedMediaRow(t, e, "m3", src, "")
	dest, err := e.SaveMessageMediaToDownloads("a1", "c1", "m3", 0)
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Base(dest) != "9f2c.jpg" {
		t.Fatalf("fallback name = %q, want 9f2c.jpg", filepath.Base(dest))
	}

	// Stored file_name with path separators: sanitized to the base.
	src2 := writeTempFile(t, srcDir, "x.bin", "bin")
	seedMediaRow(t, e, "m4", src2, "..\\evil\\name.txt")
	dest2, err := e.SaveMessageMediaToDownloads("a1", "c1", "m4", 0)
	if err != nil {
		t.Fatal(err)
	}
	base := filepath.Base(dest2)
	if base == "name.txt" && filepath.Dir(dest2) != dlDir {
		t.Fatalf("unsanitized path escaped downloads dir: %q", dest2)
	}
	if base == "" || base == "." || base == ".." || base == "/" {
		t.Fatalf("bad sanitized name %q", base)
	}
}

func TestUniqueDownloadPath(t *testing.T) {
	dir := t.TempDir()
	writeTempFile(t, dir, "a.png", "x")
	writeTempFile(t, dir, "a (1).png", "x")

	p1 := uniqueDownloadPath(dir, "a.png")
	if filepath.Base(p1) != "a (2).png" {
		t.Fatalf("uniqueDownloadPath = %q, want a (2).png", filepath.Base(p1))
	}
	p2 := uniqueDownloadPath(dir, "b.png")
	if filepath.Base(p2) != "b.png" {
		t.Fatalf("fresh name should stay: %q", filepath.Base(p2))
	}
	// Extension-less names still dedupe cleanly.
	writeTempFile(t, dir, "notes", "x")
	p3 := uniqueDownloadPath(dir, "notes")
	if filepath.Base(p3) != "notes (1)" {
		t.Fatalf("extless dedupe = %q, want notes (1)", filepath.Base(p3))
	}
}

// Ensure the SQL row scan keeps working with the exact query shape used
// by SaveMessageMediaToDownloads (guards against schema drift).
func TestSaveQueryShapeMatchesMediaTable(t *testing.T) {
	e := newTestEngine(t)
	var lp, fn sql.NullString
	err := e.db.QueryRow(
		`SELECT local_path, file_name FROM media WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = ?`,
		"a1", "c1", "zz", 0,
	).Scan(&lp, &fn)
	if err != sql.ErrNoRows {
		t.Fatalf("err = %v, want sql.ErrNoRows", err)
	}
}
