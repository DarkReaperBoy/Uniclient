package engine

// tests-first for slice 228 — ranged media streaming, the engine half of
// parity row 281 ("Playback without full download"). The core half is
// Telegram's chunked upload.getFile; what must be pinned here is the
// engine half's contract:
//
//   - fetch ONLY the byte ranges the reader touches (the measurement the
//     whole row rests on — a "streaming" reader that reads the whole
//     file is a download with extra steps),
//   - seek anywhere without downloading the bytes in between,
//   - promote itself to a completed download exactly once, at the same
//     canonical path executeDownload writes, so cache accounting and
//     eviction keep working unchanged,
//   - NEVER serve an unfetched region as silent zeros: if a range cannot
//     be fetched, the read errors (§1.10 — a corrupt first frame from a
//     silent partial read would be fake playback).

import (
	"bytes"
	"errors"
	"io"
	"os"
	"path/filepath"
	"sync"
	"testing"

	"uniclient/cores"
)

// fakePartSource serves a deterministic byte pattern by range and records
// exactly what the stream asked for.
type fakePartSource struct {
	data []byte

	mu    sync.Mutex
	calls int
	got   int64
	fail  error // when set, every fetch fails
}

func (f *fakePartSource) ReadFilePart(_ cores.FileRef, offset, limit int64) ([]byte, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.fail != nil {
		return nil, f.fail
	}
	if offset < 0 || offset > int64(len(f.data)) {
		return nil, errors.New("offset out of range")
	}
	end := offset + limit
	if end > int64(len(f.data)) {
		end = int64(len(f.data))
	}
	f.calls++
	f.got += end - offset
	return append([]byte(nil), f.data[offset:end]...), nil
}

func (f *fakePartSource) stats() (calls int, got int64) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.calls, f.got
}

// streamPattern is the deterministic content every test compares against.
func streamPattern(n int) []byte {
	b := make([]byte, n)
	for i := range b {
		b[i] = byte((i*31 + i/256) % 251)
	}
	return b
}

// newStreamForTest builds a stream over a fresh file, bypassing the DB
// row (the row-level wiring has its own test below).
func newStreamForTest(t *testing.T, src *fakePartSource, chunk int64, onDone func()) *mediaStream {
	t.Helper()
	path := filepath.Join(t.TempDir(), "clip.mp4")
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	s, err := newMediaStream(f, int64(len(src.data)), chunk, src, cores.FileRef{}, onDone)
	if err != nil {
		f.Close()
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	return s
}

// TestMediaStreamReadAtMatchesSource: exact bytes across chunk
// boundaries, at the tail, and past EOF (ReaderAt semantics).
func TestMediaStreamReadAtMatchesSource(t *testing.T) {
	data := streamPattern(100_000)
	src := &fakePartSource{data: data}
	s := newStreamForTest(t, src, 4096, nil)

	cases := []struct {
		off int64
		n   int
	}{
		{0, 100},        // head
		{4090, 20},      // crosses a chunk boundary
		{99_000, 1_000}, // tail, exactly to EOF
		{50_000, 8_192}, // interior, multi-chunk
		{99_990, 100},   // starts 10 bytes before EOF
	}
	for _, tc := range cases {
		got := make([]byte, tc.n)
		n, err := s.ReadAt(got, tc.off)
		want := data[tc.off:]
		if n > len(want) {
			t.Fatalf("ReadAt(%d,%d): n=%d past file end", tc.off, tc.n, n)
		}
		if n < tc.n && err != io.EOF {
			t.Errorf("ReadAt(%d,%d): n=%d err=%v, want io.EOF at tail", tc.off, tc.n, n, err)
		}
		for i := 0; i < n; i++ {
			if got[i] != want[i] {
				t.Fatalf("ReadAt(%d,%d): byte %d = %d, want %d", tc.off, tc.n, i, got[i], want[i])
			}
		}
	}
	// Past EOF: EOF, never fabricated bytes.
	n, err := s.ReadAt(make([]byte, 10), int64(len(data))+100)
	if n != 0 || err != io.EOF {
		t.Errorf("ReadAt past EOF = (%d,%v), want (0, io.EOF)", n, err)
	}
}

// TestMediaStreamFetchesOnlyTouchedRanges is THE row-281 proof: reading
// the first 8 KiB of a 1 MiB file must fetch KiBs, not MiBs.
func TestMediaStreamFetchesOnlyTouchedRanges(t *testing.T) {
	const size = 1 << 20 // 1 MiB
	const chunk = 4096
	data := streamPattern(size)
	src := &fakePartSource{data: data}
	s := newStreamForTest(t, src, chunk, nil)

	got := make([]byte, 8192)
	if _, err := s.ReadAt(got, 0); err != nil {
		t.Fatalf("read head: %v", err)
	}
	for i := range got {
		if got[i] != data[i] {
			t.Fatalf("head byte %d wrong", i)
		}
	}
	calls, bytesFetched := src.stats()
	// Head read touches chunks 0 and 1; readahead may fetch chunk 2.
	if calls > 3 || bytesFetched > 3*chunk {
		t.Errorf("head read fetched calls=%d bytes=%d, want ≤3/≤%d", calls, bytesFetched, 3*chunk)
	}
	if bytesFetched >= size/4 {
		t.Errorf("head read fetched %d of %d bytes — that is not streaming", bytesFetched, size)
	}
}

// TestMediaStreamSeekDoesNotFetchBetween: seeking to the middle fetches
// around the target only — the bytes between head and target stay
// unfetched.
func TestMediaStreamSeekDoesNotFetchBetween(t *testing.T) {
	const size = 1 << 20
	const chunk = 4096
	data := streamPattern(size)
	src := &fakePartSource{data: data}
	s := newStreamForTest(t, src, chunk, nil)

	r := io.NewSectionReader(s, 0, size)
	if _, err := r.Seek(500_000, io.SeekStart); err != nil {
		t.Fatal(err)
	}
	got := make([]byte, 1000)
	if _, err := io.ReadFull(r, got); err != nil {
		t.Fatalf("read at seek target: %v", err)
	}
	for i := range got {
		if got[i] != data[500_000+int64(i)] {
			t.Fatalf("post-seek byte %d wrong", i)
		}
	}
	_, bytesFetched := src.stats()
	if bytesFetched >= 500_000 {
		t.Errorf("seek-to-middle fetched %d bytes — everything up to the target came along", bytesFetched)
	}
	if bytesFetched > 3*chunk {
		t.Errorf("seek+read1000 fetched %d bytes, want ≤ %d", bytesFetched, 3*chunk)
	}
}

// TestMediaStreamCompletesExactlyOnce: reading every byte promotes the
// stream to a completed download exactly once, no matter how many more
// reads follow.
func TestMediaStreamCompletesExactlyOnce(t *testing.T) {
	const size = 20_000
	data := streamPattern(size)
	src := &fakePartSource{data: data}
	done := 0
	s := newStreamForTest(t, src, 4096, func() { done++ })

	r := io.NewSectionReader(s, 0, size)
	if _, err := io.Copy(io.Discard, r); err != nil {
		t.Fatalf("read whole: %v", err)
	}
	if done != 1 {
		t.Fatalf("onDone = %d calls after full read, want 1", done)
	}
	if !s.complete() {
		t.Errorf("stream not marked complete after every byte arrived")
	}
	// More reads after completion: still exactly one promotion.
	if _, err := r.Seek(0, io.SeekStart); err != nil {
		t.Fatal(err)
	}
	if _, err := io.Copy(io.Discard, r); err != nil {
		t.Fatalf("re-read: %v", err)
	}
	if done != 1 {
		t.Errorf("onDone = %d calls after re-read, want 1", done)
	}
}

// TestMediaStreamFetchErrorIsNotSilence: a failed range fetch must error
// the read — serving zeros would decode as a corrupt frame (fake
// playback, §1.10).
func TestMediaStreamFetchErrorIsNotSilence(t *testing.T) {
	data := streamPattern(16_384)
	src := &fakePartSource{data: data, fail: errors.New("dc unreachable")}
	s := newStreamForTest(t, src, 4096, nil)

	got := make([]byte, 1024)
	n, err := s.ReadAt(got, 0)
	if err == nil {
		t.Fatalf("ReadAt with failing fetch: err=nil (n=%d) — unfetched zeros must never be served as success", n)
	}
	if errors.Is(err, io.EOF) {
		t.Errorf("fetch failure misreported as EOF: %v", err)
	}
	if err != nil && n > 0 {
		// Partial data fetched before the failure is fine, but the error
		// must be reported so the caller does not treat it as complete.
		t.Logf("partial n=%d with error (acceptable): %v", n, err)
	}
}

// TestMediaStreamConcurrentReads: the producer goroutine reads while the
// frame thread may seek — every goroutine must see exact bytes and the
// chunk bookkeeping must stay consistent (-race in the gate).
func TestMediaStreamConcurrentReads(t *testing.T) {
	const size = 1 << 20
	data := streamPattern(size)
	src := &fakePartSource{data: data}
	s := newStreamForTest(t, src, 8192, nil)

	var wg sync.WaitGroup
	offsets := []int64{0, 4096, 65_536, 500_000, 999_000, 1_040_000}
	for _, off := range offsets {
		for rep := 0; rep < 4; rep++ {
			off := off
			wg.Add(1)
			go func() {
				defer wg.Done()
				got := make([]byte, 2048)
				n, err := s.ReadAt(got, off)
				if err != nil && err != io.EOF {
					t.Errorf("ReadAt(%d): %v", off, err)
					return
				}
				for i := 0; i < n; i++ {
					if got[i] != data[off+int64(i)] {
						t.Errorf("ReadAt(%d): byte %d wrong", off, i)
						return
					}
				}
			}()
		}
	}
	wg.Wait()
}

// TestOpenMediaStreamPromotesRow: the row-level builder picks the SAME
// canonical path executeDownload writes, and when the last byte arrives
// the media row flips to DownloadComplete with that path — one cache
// accounting path, not two. Also checks the file on disk holds the exact
// bytes afterwards (streaming must end in a valid full file).
func TestOpenMediaStreamPromotesRow(t *testing.T) {
	e := newTestEngine(t)
	e.mediaDir = t.TempDir()

	data := streamPattern(16_384)
	src := &fakePartSource{data: data}
	seedStreamRow(t, e, int64(len(data)), DownloadNone, "")

	s, size, err := e.openMediaStream("a1", "c1", "m1", 0, src)
	if err != nil {
		t.Fatalf("openMediaStream: %v", err)
	}
	if size != int64(len(data)) {
		t.Errorf("size = %d, want %d", size, len(data))
	}
	if _, err := io.Copy(io.Discard, io.NewSectionReader(s, 0, size)); err != nil {
		t.Fatalf("read whole stream: %v", err)
	}
	defer s.Close()

	// The canonical path lives under mediaDir/a1/full/<msgID>_<seq>.<ext>.
	var (
		state     int
		localPath string
	)
	err = e.db.QueryRow(
		`SELECT download_state, local_path FROM media
		 WHERE account_id='a1' AND chat_id='c1' AND msg_id='m1' AND seq=0`).
		Scan(&state, &localPath)
	if err != nil {
		t.Fatalf("read back row: %v", err)
	}
	if state != DownloadComplete {
		t.Errorf("download_state = %d, want DownloadComplete(%d)", state, DownloadComplete)
	}
	if localPath == "" {
		t.Fatalf("local_path empty after completion")
	}
	wantSuffix := filepath.Join("a1", "full", "m1_0.mp4")
	if filepath.ToSlash(filepath.Base(localPath)) != "m1_0.mp4" ||
		filepath.Base(filepath.Dir(localPath)) != "full" {
		t.Errorf("local_path = %q, want …/%s", localPath, wantSuffix)
	}
	got, err := os.ReadFile(localPath)
	if err != nil {
		t.Fatalf("read completed file: %v", err)
	}
	if !bytes.Equal(got, data) {
		t.Errorf("completed file differs from source (%d vs %d bytes or content mismatch)", len(got), len(data))
	}
}

// TestOpenMediaStreamFastPathSkipsFetch: a fully downloaded file is
// served straight from disk — no core, no ranged fetch, zero network.
func TestOpenMediaStreamFastPathSkipsFetch(t *testing.T) {
	e := newTestEngine(t)
	e.mediaDir = t.TempDir()

	data := streamPattern(8_192)
	// Pre-write the completed file exactly where executeDownload put it.
	dir := filepath.Join(e.mediaDir, "a1", "full")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "m1_0.mp4")
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
	seedStreamRow(t, e, int64(len(data)), DownloadComplete, path)

	// No account/core exists on this engine: the fast path must not need
	// one (and any attempt to fetch would fail loudly).
	s, size, err := e.OpenMediaStream("a1", "c1", "m1", 0)
	if err != nil {
		t.Fatalf("fast path: %v", err)
	}
	defer s.Close()
	if size != int64(len(data)) {
		t.Errorf("size = %d, want %d", size, len(data))
	}
	got, err := io.ReadAll(io.NewSectionReader(s, 0, size))
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if !bytes.Equal(got, data) {
		t.Errorf("fast-path bytes differ from the file on disk")
	}
}

// TestResolveStreamSourceRejectsUnsupported: cores without ranged reads
// get ErrNoRangedRead (the caller keeps the download-then-play path) —
// never a panic on a failed type assertion.
func TestResolveStreamSourceRejectsUnsupported(t *testing.T) {
	if _, err := resolveStreamSource(nil); !errors.Is(err, ErrNoRangedRead) {
		t.Errorf("nil core: err = %v, want ErrNoRangedRead", err)
	}
	if _, err := resolveStreamSource(struct{}{}); !errors.Is(err, ErrNoRangedRead) {
		t.Errorf("core without ranged read: err = %v, want ErrNoRangedRead", err)
	}
	src := &fakePartSource{}
	got, err := resolveStreamSource(src)
	if err != nil || got == nil {
		t.Errorf("ranged core: got (%v, %v), want (source, nil)", got, err)
	}
}

// seedStreamRow inserts the media row streaming reads.
func seedStreamRow(t *testing.T, e *Engine, size int64, state int, localPath string) {
	t.Helper()
	var path any
	if localPath != "" {
		path = localPath
	}
	_, err := e.db.Exec(
		`INSERT INTO media (account_id, chat_id, msg_id, seq, media_type, remote_ref,
			file_name, mime_type, file_size, download_state, local_path, extra)
		 VALUES ('a1','c1','m1',0,1,'REF-1','clip.mp4','video/mp4',?,?,?,'777:Zm9v')`,
		size, state, path)
	if err != nil {
		t.Fatal(err)
	}
}
