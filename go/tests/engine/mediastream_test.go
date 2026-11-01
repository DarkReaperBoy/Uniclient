package tests

import (
	"bytes"
	"errors"
	"io"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
	. "uniclient/engine"

	"uniclient/cores"
)

type fakePartSource struct {
	data []byte

	mu    sync.Mutex
	calls int
	got   int64
	fail  error
	delay time.Duration
}

func (f *fakePartSource) ReadFilePart(_ cores.FileRef, offset, limit int64) ([]byte, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.fail != nil {
		return nil, f.fail
	}
	if f.delay > 0 {
		time.Sleep(f.delay)
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

func streamPattern(n int) []byte {
	b := make([]byte, n)
	for i := range b {
		b[i] = byte((i*31 + i/256) % 251)
	}
	return b
}

func newStreamForTest(t *testing.T, src *fakePartSource, chunk int64, onDone func()) *MediaStream {
	t.Helper()
	path := filepath.Join(t.TempDir(), "clip.mp4")
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	s, err := NewMediaStream(f, int64(len(src.data)), chunk, src, cores.FileRef{}, onDone)
	if err != nil {
		f.Close()
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	return s
}

func TestMediaStreamReadAtMatchesSource(t *testing.T) {
	data := streamPattern(100_000)
	src := &fakePartSource{data: data}
	s := newStreamForTest(t, src, 4096, nil)

	cases := []struct {
		off int64
		n   int
	}{
		{0, 100},
		{4090, 20},
		{99_000, 1_000},
		{50_000, 8_192},
		{99_990, 100},
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
	n, err := s.ReadAt(make([]byte, 10), int64(len(data))+100)
	if n != 0 || err != io.EOF {
		t.Errorf("ReadAt past EOF = (%d,%v), want (0, io.EOF)", n, err)
	}
}

func TestMediaStreamFetchesOnlyTouchedRanges(t *testing.T) {
	const size = 1 << 20
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
	if calls > 3 || bytesFetched > 3*chunk {
		t.Errorf("head read fetched calls=%d bytes=%d, want ≤3/≤%d", calls, bytesFetched, 3*chunk)
	}
	if bytesFetched >= size/4 {
		t.Errorf("head read fetched %d of %d bytes — that is not streaming", bytesFetched, size)
	}
}

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
	if !s.ForTestComplete() {
		t.Errorf("stream not marked complete after every byte arrived")
	}
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
		t.Logf("partial n=%d with error (acceptable): %v", n, err)
	}
}

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

func TestOpenMediaStreamPromotesRow(t *testing.T) {
	e := newTestEngine(t)
	e.ForTestSetMediaDir(t.TempDir())

	data := streamPattern(16_384)
	src := &fakePartSource{data: data}
	seedStreamRow(t, e, int64(len(data)), DownloadNone, "")

	s, pth, size, err := e.ForTestOpenMediaStream("a1", "c1", "m1", 0, src)
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

	var (
		state     int
		localPath string
	)
	err = e.ForTestDb().QueryRow(
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
	if pth != localPath {
		t.Errorf("returned path %q != promoted local_path %q — the GUI would key its player cache differently and re-parse on completion", pth, localPath)
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

func TestOpenMediaStreamFastPathSkipsFetch(t *testing.T) {
	e := newTestEngine(t)
	e.ForTestSetMediaDir(t.TempDir())

	data := streamPattern(8_192)
	dir := filepath.Join(e.MediaDir(), "a1", "full")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "m1_0.mp4")
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
	seedStreamRow(t, e, int64(len(data)), DownloadComplete, path)

	s, size, pth, err := e.OpenMediaStream("a1", "c1", "m1", 0)
	if err != nil {
		t.Fatalf("fast path: %v", err)
	}
	defer s.Close()
	if pth != path {
		t.Errorf("fast path returned %q, want the completed file's path %q", pth, path)
	}
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

func TestResolveStreamSourceRejectsUnsupported(t *testing.T) {
	if _, err := ResolveStreamSource(nil); !errors.Is(err, ErrNoRangedRead) {
		t.Errorf("nil core: err = %v, want ErrNoRangedRead", err)
	}
	if _, err := ResolveStreamSource(struct{}{}); !errors.Is(err, ErrNoRangedRead) {
		t.Errorf("core without ranged read: err = %v, want ErrNoRangedRead", err)
	}
	src := &fakePartSource{}
	got, err := ResolveStreamSource(src)
	if err != nil || got == nil {
		t.Errorf("ranged core: got (%v, %v), want (source, nil)", got, err)
	}
}

func TestMediaStreamSingleFlightPerChunk(t *testing.T) {
	const size = 256 << 10
	const chunk = 8192
	data := streamPattern(size)
	ceil := (size + chunk - 1) / chunk

	t.Run("eight readers of one chunk share a single fetch", func(t *testing.T) {
		src := &fakePartSource{data: data, delay: 80 * time.Millisecond}
		s := newStreamForTest(t, src, chunk, nil)
		var start, wg sync.WaitGroup
		start.Add(1)
		for i := 0; i < 8; i++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				start.Wait()
				got := make([]byte, 1024)
				n, err := s.ReadAt(got, 4096)
				if err != nil && err != io.EOF {
					t.Errorf("ReadAt: %v", err)
					return
				}
				if n != 1024 || !bytes.Equal(got[:n], data[4096:4096+n]) {
					t.Errorf("ReadAt bytes wrong (n=%d)", n)
				}
			}()
		}
		start.Done()
		wg.Wait()
		if calls, _ := src.stats(); calls != 1 {
			t.Errorf("chunk RPCs = %d, want 1 (per-chunk single-flight)", calls)
		}
	})

	t.Run("concurrent whole-file readers cost exactly ceil(size/chunk)", func(t *testing.T) {
		src := &fakePartSource{data: data, delay: 5 * time.Millisecond}
		s := newStreamForTest(t, src, chunk, nil)
		var wg sync.WaitGroup
		for r := 0; r < 4; r++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				buf := make([]byte, 4096)
				var off int64
				for off < size {
					n, err := s.ReadAt(buf, off)
					if err != nil && err != io.EOF {
						t.Errorf("ReadAt(%d): %v", off, err)
						return
					}
					if n == 0 {
						return
					}
					off += int64(n)
				}
			}()
		}
		wg.Wait()
		calls, fetched := src.stats()
		if calls != ceil {
			t.Errorf("RPC calls = %d, want %d — every chunk exactly once, no duplicates", calls, ceil)
		}
		if fetched != size {
			t.Errorf("bytes fetched = %d, want %d (whole file, each byte once)", fetched, size)
		}
	})
}

func seedStreamRow(t *testing.T, e *Engine, size int64, state int, localPath string) {
	t.Helper()
	var path any
	if localPath != "" {
		path = localPath
	}
	_, err := e.ForTestDb().Exec(
		`INSERT INTO media (account_id, chat_id, msg_id, seq, media_type, remote_ref,
			file_name, mime_type, file_size, download_state, local_path, extra)
		 VALUES ('a1','c1','m1',0,1,'REF-1','clip.mp4','video/mp4',?,?,?,'777:Zm9v')`,
		size, state, path)
	if err != nil {
		t.Fatal(err)
	}
}

func TestMediaStreamDoneOnlyAfterLastChunk(t *testing.T) {
	const chunk = 1 << 16
	data := streamPattern(chunk * 3)
	src := &fakePartSource{data: data}

	var mu sync.Mutex
	dones := 0
	s := newStreamForTest(t, src, chunk, func() {
		mu.Lock()
		dones++
		mu.Unlock()
	})
	doneCount := func() int {
		mu.Lock()
		defer mu.Unlock()
		return dones
	}
	readAt := func(off int64) {
		t.Helper()
		buf := make([]byte, 8)
		if _, err := s.ReadAt(buf, off); err != nil {
			t.Fatalf("ReadAt(%d): %v", off, err)
		}
	}

	readAt(0)
	if got := doneCount(); got != 0 {
		t.Fatalf("onDone fired after chunk 0 of 3 (%d) — stream promoted complete while 2/3 of the file is still holes (B-10)", got)
	}
	readAt(int64(chunk))
	if got := doneCount(); got != 0 {
		t.Fatalf("onDone fired after chunk 1 of 3 (%d) — still not complete (B-10)", got)
	}
	readAt(int64(2 * chunk))
	if got := doneCount(); got != 1 {
		t.Fatalf("onDone count after the last chunk = %d, want 1", got)
	}
	readAt(0)
	if got := doneCount(); got != 1 {
		t.Fatalf("onDone fired %d times total, want exactly 1", got)
	}
}
