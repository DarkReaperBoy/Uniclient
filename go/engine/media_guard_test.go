package engine

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"uniclient/cores"
)

type guardCore struct {
	cores.StubCore

	mu      sync.Mutex
	dlCalls int
	part    *fakePartSource
	dlErr   error
}

func (g *guardCore) DownloadFile(_ cores.FileRef, dest string, _ func(int64, int64)) error {
	g.mu.Lock()
	g.dlCalls++
	part := g.part
	dlErr := g.dlErr
	g.mu.Unlock()
	if dlErr != nil {
		os.WriteFile(dest, []byte("partial-bytes"), 0o644)
		return dlErr
	}
	if part == nil {
		return os.WriteFile(dest, []byte("x"), 0o644)
	}
	return os.WriteFile(dest, part.data, 0o644)
}

func (g *guardCore) ReadFilePart(ref cores.FileRef, off, lim int64) ([]byte, error) {
	return g.part.ReadFilePart(ref, off, lim)
}

func (g *guardCore) downloads() int {
	g.mu.Lock()
	defer g.mu.Unlock()
	return g.dlCalls
}

func newGuardEngine(t *testing.T) (*Engine, *guardCore, []byte) {
	t.Helper()
	e := newTestEngine(t)
	e.mediaDir = t.TempDir()
	e.media = newMediaManager(e)
	data := streamPattern(16_384)
	core := &guardCore{part: &fakePartSource{data: data}}
	e.accounts = map[string]*Account{"a1": {ID: "a1", Core: core}}
	seedStreamRow(t, e, int64(len(data)), DownloadNone, "")
	return e, core, data
}

func TestRequestDownloadRefusedWhileStreamOpen(t *testing.T) {
	e, _, _ := newGuardEngine(t)

	s, _, _, err := e.OpenMediaStream("a1", "c1", "m1", 0)
	if err != nil {
		t.Fatalf("OpenMediaStream: %v", err)
	}
	if err := e.RequestDownload("a1", "c1", "m1", 0, 0); !errors.Is(err, ErrStreamActive) {
		t.Fatalf("RequestDownload during stream = %v, want ErrStreamActive", err)
	}
	if n := len(e.media.queue); n != 0 {
		t.Errorf("queue holds %d jobs during a stream, want 0", n)
	}
	if core := e.getAccountCore(t); core.downloads() != 0 {
		t.Errorf("core DownloadFile ran %d times during a stream", core.downloads())
	}

	if err := s.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	if err := e.RequestDownload("a1", "c1", "m1", 0, 0); err != nil {
		t.Fatalf("RequestDownload after Close: %v (the fallback flow must enqueue)", err)
	}
	if n := len(e.media.queue); n != 1 {
		t.Errorf("queue = %d jobs after Close, want 1", n)
	}
}

func TestOpenMediaStreamRefusedWhileDownloadActive(t *testing.T) {
	e, _, _ := newGuardEngine(t)
	key := mediaGuardKey("a1", "c1", "m1", 0)

	if !e.claimDownload(key) {
		t.Fatal("seed: claimDownload")
	}
	if _, _, _, err := e.OpenMediaStream("a1", "c1", "m1", 0); !errors.Is(err, ErrStreamBusy) {
		t.Fatalf("OpenMediaStream during download = %v, want ErrStreamBusy", err)
	}
	e.releaseDownload(key)

	s, _, _, err := e.OpenMediaStream("a1", "c1", "m1", 0)
	if err != nil {
		t.Fatalf("OpenMediaStream after download released: %v", err)
	}
	s.Close()
}

func TestExecuteDownloadSkipsWhileStreamOpen(t *testing.T) {
	e, core, _ := newGuardEngine(t)

	s, _, _, err := e.openMediaStream("a1", "c1", "m1", 0, core)
	if err != nil {
		t.Fatalf("openMediaStream: %v", err)
	}
	job := &downloadJob{
		AccountID: "a1", ChatID: "c1", MsgID: "m1", Seq: 0,
		RemoteRef: "REF-1", FileName: "clip.mp4", MimeType: "video/mp4", Extra: "777:Zm9v",
	}
	e.media.executeDownload(job)

	if core.downloads() != 0 {
		t.Errorf("DownloadFile ran %d times while a stream owns the file", core.downloads())
	}
	var st int
	if err := e.db.QueryRow(
		`SELECT download_state FROM media WHERE account_id='a1' AND chat_id='c1' AND msg_id='m1' AND seq=0`).
		Scan(&st); err != nil {
		t.Fatal(err)
	}
	if st != DownloadNone {
		t.Errorf("download_state = %d during a stream, want untouched DownloadNone(%d)", st, DownloadNone)
	}

	s.Close()
	e.media.executeDownload(job)
	if core.downloads() != 1 {
		t.Fatalf("DownloadFile ran %d times after the stream closed, want 1", core.downloads())
	}
	if err := e.db.QueryRow(
		`SELECT download_state FROM media WHERE account_id='a1' AND chat_id='c1' AND msg_id='m1' AND seq=0`).
		Scan(&st); err != nil {
		t.Fatal(err)
	}
	if st != DownloadComplete {
		t.Errorf("download_state = %d after a real download, want DownloadComplete(%d)", st, DownloadComplete)
	}
}

func TestRequestDownloadCompletesInstantlyWhenFileOnDisk(t *testing.T) {
	e, core, data := newGuardEngine(t)

	dir := filepath.Join(e.mediaDir, "a1", "full")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "m1_0.mp4")
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := e.db.Exec(
		`UPDATE media SET download_state=?, local_path=?
		 WHERE account_id='a1' AND chat_id='c1' AND msg_id='m1' AND seq=0`,
		DownloadComplete, path); err != nil {
		t.Fatal(err)
	}

	rec := &evRecorder{}
	sub := e.Subscribe(rec.record)
	defer sub.Unsubscribe()

	if err := e.RequestDownload("a1", "c1", "m1", 0, 0); err != nil {
		t.Fatalf("RequestDownload on a completed row: %v", err)
	}
	if n := len(e.media.queue); n != 0 {
		t.Errorf("queue = %d jobs for an already-downloaded file, want 0", n)
	}
	if core.downloads() != 0 {
		t.Errorf("DownloadFile ran for an already-downloaded file")
	}
	if !rec.has(EventDownloadComplete) {
		t.Errorf("no download_complete event — markers set on this row would never fire (dead tap)")
	}
}

func TestStreamGuardSurvivesDoubleClose(t *testing.T) {
	e, _, _ := newGuardEngine(t)
	key := mediaGuardKey("a1", "c1", "m1", 0)

	s, _, _, err := e.OpenMediaStream("a1", "c1", "m1", 0)
	if err != nil {
		t.Fatal(err)
	}
	if e.claimDownload(key) {
		t.Error("download claimed the key while the stream held it")
	}
	s.Close()
	s.Close()

	s2, _, _, err := e.OpenMediaStream("a1", "c1", "m1", 0)
	if err != nil {
		t.Fatalf("re-open after double close: %v", err)
	}
	s2.Close()
	if !e.claimDownload(key) {
		t.Error("download cannot claim the key after every stream closed — guard leaked or underflowed")
	}
	e.releaseDownload(key)
}

func (e *Engine) getAccountCore(t *testing.T) *guardCore {
	t.Helper()
	acc, ok := e.getAccount("a1")
	if !ok || acc.Core == nil {
		t.Fatal("account a1 has no core")
	}
	c, ok := acc.Core.(*guardCore)
	if !ok {
		t.Fatal("account core is not *guardCore")
	}
	return c
}

type evRecorder struct {
	mu  sync.Mutex
	got []string
}

func (r *evRecorder) record(b []byte) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.got = append(r.got, string(b))
}

func (r *evRecorder) has(substring string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	for _, s := range r.got {
		if strings.Contains(s, substring) {
			return true
		}
	}
	return false
}
