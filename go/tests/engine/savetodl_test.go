package tests

import (
	"database/sql"
	"errors"
	"os"
	"path/filepath"
	"testing"
	. "uniclient/engine"

	"uniclient/cores"
	"uniclient/utils"
)

func seedMediaRow(t *testing.T, e *dbEngine, msgID, localPath, fileName string) {
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
	e := newSaveToDownloadsEngine(t, t.TempDir())
	srcDir := t.TempDir()
	dlDir := t.TempDir()
	e.UpdateConfigFromBridge(&ConfigChanges{DownloadDir: dlDir})

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
	if _, err := os.Stat(src); err != nil {
		t.Fatalf("cache copy vanished: %v", err)
	}
}

func TestSaveMessageMediaDedupNeverOverwrites(t *testing.T) {
	e := newSaveToDownloadsEngine(t, t.TempDir())
	srcDir := t.TempDir()
	dlDir := t.TempDir()
	e.UpdateConfigFromBridge(&ConfigChanges{DownloadDir: dlDir})

	src := writeTempFile(t, srcDir, "cache.bin", "first")
	seedMediaRow(t, e, "m1", src, "same.png")

	d1, err := e.SaveMessageMediaToDownloads("a1", "c1", "m1", 0)
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Base(d1) != "same.png" {
		t.Fatalf("first save name = %q, want same.png", filepath.Base(d1))
	}
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
	e := newSaveToDownloadsEngine(t, t.TempDir())
	seedMediaRow(t, e, "m2", "", "doc.pdf")

	_, err := e.SaveMessageMediaToDownloads("a1", "c1", "m2", 0)
	if !errors.Is(err, ErrMediaNotDownloaded) {
		t.Fatalf("err = %v, want ErrMediaNotDownloaded", err)
	}
}

func TestSaveMessageMediaMissingRow(t *testing.T) {
	e := newSaveToDownloadsEngine(t, t.TempDir())
	if _, err := e.SaveMessageMediaToDownloads("a1", "c1", "nope", 0); err == nil {
		t.Fatal("missing media row must error")
	}
}

func TestSaveMessageMediaFileNameFallbacks(t *testing.T) {
	e := newSaveToDownloadsEngine(t, t.TempDir())
	srcDir := t.TempDir()
	dlDir := t.TempDir()
	e.UpdateConfigFromBridge(&ConfigChanges{DownloadDir: dlDir})

	src := writeTempFile(t, srcDir, "9f2c.jpg", "img")
	seedMediaRow(t, e, "m3", src, "")
	dest, err := e.SaveMessageMediaToDownloads("a1", "c1", "m3", 0)
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Base(dest) != "9f2c.jpg" {
		t.Fatalf("fallback name = %q, want 9f2c.jpg", filepath.Base(dest))
	}

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

func newSaveToDownloadsEngine(t *testing.T, dir string) *dbEngine {
	t.Helper()
	v, err := utils.CreateVault(filepath.Join(t.TempDir(), "vault.db"), "test")
	if err != nil {
		t.Fatal(err)
	}
	cfg := utils.DefaultConfig()
	cfg.DownloadDir = dir
	return newTestEngineWith(t, v, &cfg)
}

func TestBridgeDownloadDirChangeSteersSavePath(t *testing.T) {
	v, err := utils.CreateVault(filepath.Join(t.TempDir(), "vault.db"), "test")
	if err != nil {
		t.Fatal(err)
	}
	defer v.Close()
	oldDir := t.TempDir()
	cfg := utils.DefaultConfig()
	cfg.DownloadDir = oldDir
	e := newTestEngineWith(t, v, &cfg)

	src := writeTempFile(t, t.TempDir(), "cache.bin", "payload")
	seedMediaRow(t, e, "m1", src, "file.bin")

	dest, err := e.SaveMessageMediaToDownloads("a1", "c1", "m1", 0)
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Dir(dest) != oldDir {
		t.Fatalf("initial save dir = %q, want %q", filepath.Dir(dest), oldDir)
	}

	fresh := filepath.Join(t.TempDir(), "nested", "downloads")
	if err := e.UpdateConfigFromBridge(&ConfigChanges{DownloadDir: fresh}); err != nil {
		t.Fatal(err)
	}
	dest2, err := e.SaveMessageMediaToDownloads("a1", "c1", "m1", 0)
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Dir(dest2) != fresh {
		t.Fatalf("save after bridge change = %q, want %q (runtime download dir never moved)", filepath.Dir(dest2), fresh)
	}
}

func TestUniqueDownloadPath(t *testing.T) {
	dir := t.TempDir()
	writeTempFile(t, dir, "a.png", "x")
	writeTempFile(t, dir, "a (1).png", "x")

	p1 := UniqueDownloadPath(dir, "a.png")
	if filepath.Base(p1) != "a (2).png" {
		t.Fatalf("uniqueDownloadPath = %q, want a (2).png", filepath.Base(p1))
	}
	p2 := UniqueDownloadPath(dir, "b.png")
	if filepath.Base(p2) != "b.png" {
		t.Fatalf("fresh name should stay: %q", filepath.Base(p2))
	}
	writeTempFile(t, dir, "notes", "x")
	p3 := UniqueDownloadPath(dir, "notes")
	if filepath.Base(p3) != "notes (1)" {
		t.Fatalf("extless dedupe = %q, want notes (1)", filepath.Base(p3))
	}
}

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

type takeoutStub struct{ cores.StubCore }

func (takeoutStub) InitTakeout(contacts, msgUsers, msgChats, msgMegagroups, msgChannels, files bool, fileMaxSizeBytes int64) (int64, error) {
	return 1, nil
}
func (takeoutStub) FinishTakeout() error { return nil }

type plainStub struct{ cores.StubCore }

func TestSupportsTakeout(t *testing.T) {
	e := newTestEngine(t)
	if err := e.AttachAccount("tg", "telegram", takeoutStub{}); err != nil {
		t.Fatal(err)
	}
	if err := e.AttachAccount("irc", "irc", plainStub{}); err != nil {
		t.Fatal(err)
	}
	if !e.SupportsTakeout("tg") {
		t.Error("takeout-capable core reported unsupported")
	}
	if e.SupportsTakeout("irc") {
		t.Error("plain core reported takeout support")
	}
	if e.SupportsTakeout("missing") {
		t.Error("missing account reported takeout support")
	}
}
