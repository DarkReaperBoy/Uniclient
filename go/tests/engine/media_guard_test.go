package tests

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	. "uniclient/engine"

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

type blockCore struct {
	cores.StubCore

	mu       sync.Mutex
	started  int
	finished int
	gate     chan struct{}
	part     *fakePartSource
}

func newBlockCore(data []byte) *blockCore {
	return &blockCore{gate: make(chan struct{}), part: &fakePartSource{data: data}}
}

func (b *blockCore) ReadFilePart(ref cores.FileRef, off, lim int64) ([]byte, error) {
	return b.part.ReadFilePart(ref, off, lim)
}

func (b *blockCore) DownloadFile(_ cores.FileRef, dest string, _ func(int64, int64)) error {
	b.mu.Lock()
	b.started++
	b.mu.Unlock()
	<-b.gate
	b.mu.Lock()
	b.finished++
	b.mu.Unlock()
	return os.WriteFile(dest, []byte("x"), 0o644)
}

func (b *blockCore) counts() (started, finished int) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.started, b.finished
}

func waitUntil(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(2 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s", what)
}

func newGuardEngine(t *testing.T) (*dbEngine, *guardCore, []byte) {
	t.Helper()
	e := newTestEngine(t)
	if err := e.UseMediaDir(t.TempDir()); err != nil {
		t.Fatal(err)
	}
	data := streamPattern(16_384)
	core := &guardCore{part: &fakePartSource{data: data}}
	if err := e.AttachAccount("a1", "telegram", core); err != nil {
		t.Fatal(err)
	}
	seedStreamRow(t, e, int64(len(data)), DownloadNone, "")
	return e, core, data
}

func seedMediaMsgRow(t *testing.T, e *dbEngine, msgID string) {
	t.Helper()
	_, err := e.db.Exec(
		`INSERT INTO media (account_id, chat_id, msg_id, seq, media_type, remote_ref,
                        file_name, mime_type, file_size, download_state, local_path, extra)
                 VALUES ('a1','c1',?,0,1,?,?,'video/mp4',16,?,NULL,NULL)`,
		msgID, "REF-"+msgID, msgID+".mp4", DownloadNone)
	if err != nil {
		t.Fatal(err)
	}
}

func TestRequestDownloadRefusedWhileStreamOpen(t *testing.T) {
	e, _, _ := newGuardEngine(t)

	rec := &evRecorder{}
	sub := e.Subscribe(rec.record)
	defer sub.Unsubscribe()

	s, _, _, err := e.OpenMediaStream("a1", "c1", "m1", 0)
	if err != nil {
		t.Fatalf("OpenMediaStream: %v", err)
	}
	if err := e.RequestDownload("a1", "c1", "m1", 0, 0); !errors.Is(err, ErrStreamActive) {
		t.Fatalf("RequestDownload during stream = %v, want ErrStreamActive", err)
	}
	if core := getAccountCore(e, t); core.downloads() != 0 {
		t.Errorf("core DownloadFile ran %d times during a stream", core.downloads())
	}

	if err := s.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	if err := e.RequestDownload("a1", "c1", "m1", 0, 0); err != nil {
		t.Fatalf("RequestDownload after Close: %v (the fallback flow must enqueue)", err)
	}
	waitUntil(t, "download_complete after Close", func() bool { return rec.has(EventDownloadComplete) })
	if core := getAccountCore(e, t); core.downloads() != 1 {
		t.Errorf("DownloadFile ran %d times after Close, want 1", core.downloads())
	}
}

func TestOpenMediaStreamRefusedWhileDownloadActive(t *testing.T) {
	e, _, _ := newGuardEngine(t)
	key := MediaGuardKey("a1", "c1", "m1", 0)

	if !e.ClaimDownload(key) {
		t.Fatal("seed: claimDownload")
	}
	if _, _, _, err := e.OpenMediaStream("a1", "c1", "m1", 0); !errors.Is(err, ErrStreamBusy) {
		t.Fatalf("OpenMediaStream during download = %v, want ErrStreamBusy", err)
	}
	e.ReleaseDownload(key)

	s, _, _, err := e.OpenMediaStream("a1", "c1", "m1", 0)
	if err != nil {
		t.Fatalf("OpenMediaStream after download released: %v", err)
	}
	s.Close()
}

func TestExecuteDownloadSkipsWhileStreamOpen(t *testing.T) {
	e := newTestEngine(t)
	if err := e.UseMediaDir(t.TempDir()); err != nil {
		t.Fatal(err)
	}
	core := newBlockCore(streamPattern(16))
	if err := e.AttachAccount("a1", "telegram", core); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 10; i++ {
		seedMediaMsgRow(t, e, fmt.Sprintf("b%d", i))
	}
	seedStreamRow(t, e, 16, DownloadNone, "")

	for i := 0; i < 10; i++ {
		if err := e.RequestDownload("a1", "c1", fmt.Sprintf("b%d", i), 0, 0); err != nil {
			t.Fatalf("filler RequestDownload b%d: %v", i, err)
		}
	}
	waitUntil(t, "10 filler downloads started", func() bool {
		started, _ := core.counts()
		return started == 10
	})

	if err := e.RequestDownload("a1", "c1", "m1", 0, 0); err != nil {
		t.Fatalf("RequestDownload m1: %v", err)
	}

	s, _, _, err := e.OpenMediaStream("a1", "c1", "m1", 0)
	if err != nil {
		t.Fatalf("OpenMediaStream: %v", err)
	}

	close(core.gate)
	waitUntil(t, "filler downloads finished", func() bool {
		_, finished := core.counts()
		return finished == 10
	})

	settle := time.Now().Add(500 * time.Millisecond)
	for time.Now().Before(settle) {
		if started, _ := core.counts(); started > 10 {
			t.Fatalf("DownloadFile ran %d times while a stream owned the file, want 10 (the queued job must be skipped)", started)
		}
		time.Sleep(2 * time.Millisecond)
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

	rec := &evRecorder{}
	sub := e.Subscribe(rec.record)
	defer sub.Unsubscribe()

	if err := s.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	if err := e.RequestDownload("a1", "c1", "m1", 0, 0); err != nil {
		t.Fatalf("RequestDownload after Close: %v", err)
	}
	waitUntil(t, "m1 download_complete after re-request", func() bool { return rec.has(EventDownloadComplete) })

	started, _ := core.counts()
	if started != 11 {
		t.Fatalf("DownloadFile ran %d times, want 11 (10 fillers + 1 — the queued job must have been skipped, not executed)", started)
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

	dir := filepath.Join(e.MediaDir(), "a1", "full")
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
	if core.downloads() != 0 {
		t.Errorf("DownloadFile ran for an already-downloaded file")
	}
	if !rec.has(EventDownloadComplete) {
		t.Errorf("no download_complete event — markers set on this row would never fire (dead tap)")
	}
}

func TestStreamGuardSurvivesDoubleClose(t *testing.T) {
	e, _, _ := newGuardEngine(t)
	key := MediaGuardKey("a1", "c1", "m1", 0)

	s, _, _, err := e.OpenMediaStream("a1", "c1", "m1", 0)
	if err != nil {
		t.Fatalf("OpenMediaStream: %v", err)
	}
	if e.ClaimDownload(key) {
		t.Error("download claimed the key while the stream held it")
	}
	s.Close()
	s.Close()

	s2, _, _, err := e.OpenMediaStream("a1", "c1", "m1", 0)
	if err != nil {
		t.Fatalf("re-open after double close: %v", err)
	}
	s2.Close()
	if !e.ClaimDownload(key) {
		t.Error("download cannot claim the key after every stream closed — guard leaked or underflowed")
	}
	e.ReleaseDownload(key)
}

func getAccountCore(e *dbEngine, t *testing.T) *guardCore {
	t.Helper()
	core := e.GetAccountCore("a1")
	if core == nil {
		t.Fatal("account a1 has no core")
	}
	c, ok := core.(*guardCore)
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
