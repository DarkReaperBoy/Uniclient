// Ranged media streaming — the engine half of parity row 281 ("Playback
// without full download"), slice 228.
//
// The shape: a sparse file at the SAME canonical path executeDownload
// writes, backed by a fetch-on-read bitmap. A read first makes sure the
// chunks covering its range have arrived (chunked upload.getFile through
// the account core), then reads from disk — so playback starts after the
// first chunks instead of after the whole file, seeking fetches around
// the target only, and when the last chunk lands the row is promoted to
// DownloadComplete at that path, merging into the existing cache
// accounting instead of inventing a second one.
//
// Two rules the tests pin (mediastream_test.go):
//   - fetch only what is touched: reading the head of a 1 MiB file must
//     cost KiBs, or "streaming" is a download with extra steps;
//   - never serve an unfetched region as silent zeros: a failed fetch
//     errors the read (§1.10 — zeros would decode as a corrupt frame,
//     which is fake playback).
package engine

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"
	"time"

	"uniclient/cores"
)

// ErrNoRangedRead: the account's core cannot fetch byte ranges, so the
// caller must keep the download-then-play path (honest capability gate,
// not a fake stream).
var ErrNoRangedRead = errors.New("streaming: core cannot read byte ranges")

// streamChunk is the fetch unit: 512 KiB — divisible by 4096 (the
// upload.getFile offset rule) and well under its 1 MiB limit, so a
// mid-playback stall costs one RPC per half-megabyte.
const streamChunk = 512 << 10

// partSource is the ranged-read half a core must offer for streaming
// (Telegram: chunked upload.getFile). Cores without it keep the
// download-then-play path — see resolveStreamSource.
type partSource interface {
	ReadFilePart(fileRef cores.FileRef, offset, limit int64) ([]byte, error)
}

// resolveStreamSource extracts ranged-read capability from an account's
// core (passed as any so tests can hand it a fake without standing up
// the full Core surface). Absent capability is ErrNoRangedRead, never a
// failed-assertion panic.
func resolveStreamSource(core any) (partSource, error) {
	if core == nil {
		return nil, ErrNoRangedRead
	}
	if ps, ok := core.(partSource); ok {
		return ps, nil
	}
	return nil, ErrNoRangedRead
}

// MediaReader is what viewers get back: random access, and Close for the
// streaming case (the fast path returns the open file itself).
type MediaReader interface {
	io.ReaderAt
	io.Closer
}

// mediaStream is a fetch-on-read sparse file: ReaderAt over a chunk
// bitmap. Once have[c] is true it stays true, so after ensure returns
// the disk read needs no lock (os.File.ReadAt is concurrency-safe).
type mediaStream struct {
	mu     sync.Mutex
	f      *os.File
	size   int64
	chunk  int64
	have   []bool // per-chunk arrival bitmap
	src    partSource
	ref    cores.FileRef
	got    int64 // bytes fetched so far (the measurement)
	done   bool  // every chunk arrived
	onDone func()
}

// newMediaStream truncates f to size (sparse) and wraps it for ranged
// fetching. onDone fires exactly once, when the last chunk lands.
func newMediaStream(f *os.File, size, chunk int64, src partSource, ref cores.FileRef, onDone func()) (*mediaStream, error) {
	if f == nil {
		return nil, errors.New("stream: nil file")
	}
	if size <= 0 {
		f.Close()
		return nil, errors.New("stream: unknown size")
	}
	if chunk <= 0 {
		chunk = streamChunk
	}
	if err := f.Truncate(size); err != nil {
		f.Close()
		return nil, fmt.Errorf("stream: pre-size: %w", err)
	}
	return &mediaStream{
		f:      f,
		size:   size,
		chunk:  chunk,
		have:   make([]bool, (size+chunk-1)/chunk),
		src:    src,
		ref:    ref,
		onDone: onDone,
	}, nil
}

// Size is the total byte length the reader presents.
func (s *mediaStream) Size() int64 { return s.size }

// Fetched counts bytes actually downloaded — tests use it to prove the
// row; a future progress UI could too.
func (s *mediaStream) Fetched() int64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.got
}

func (s *mediaStream) complete() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.done
}

// ensureChunk makes chunk c present, fetching it if needed. The fetch
// runs under s.mu: readers serialize on a miss (correct first — the
// playback producer is effectively single-goroutine, and a dedup +
// readahead layer can come later without changing this contract).
func (s *mediaStream) ensureChunk(c int64) error {
	s.mu.Lock()
	if c < 0 || c >= int64(len(s.have)) {
		s.mu.Unlock()
		return fmt.Errorf("stream: chunk %d out of range", c)
	}
	if s.have[c] {
		s.mu.Unlock()
		return nil
	}
	off := c * s.chunk
	want := s.chunk
	if rem := s.size - off; rem < want {
		want = rem
	}
	src, ref := s.src, s.ref
	s.mu.Unlock()

	// Network fetch outside the lock would allow duplicate fetches on a
	// miss; v1 trades that (single producer in practice) for never
	// holding the bookkeeping lock across an RPC that a Close/complete
	// check might need. Fetch first, then claim under the lock.
	data, err := src.ReadFilePart(ref, off, want)
	if err != nil {
		return fmt.Errorf("stream: fetch chunk %d: %w", c, err)
	}
	if int64(len(data)) != want {
		// A short/long range is a protocol violation; serving it would
		// silently shift every later byte (§1.10: fail, don't fudge).
		return fmt.Errorf("stream: chunk %d: got %d bytes, want %d", c, len(data), want)
	}

	s.mu.Lock()
	n, err := s.f.WriteAt(data, off)
	if err == nil && int64(n) != want {
		err = io.ErrShortWrite
	}
	if err != nil {
		s.mu.Unlock()
		return fmt.Errorf("stream: cache chunk %d: %w", c, err)
	}
	if !s.have[c] {
		s.have[c] = true
		s.got += want
	}
	justDone := false
	if !s.done {
		for _, ok := range s.have {
			if !ok {
				break
			}
			// all present
			s.done = true
			justDone = true
			break
		}
	}
	cb := s.onDone
	if justDone {
		s.onDone = nil // exactly-once, enforced under the lock
	}
	s.mu.Unlock()

	if justDone && cb != nil {
		cb() // DB promotion + event; does not re-enter the stream
	}
	return nil
}

// ensure makes every chunk covering [off, off+n) present.
func (s *mediaStream) ensure(off, n int64) error {
	if n <= 0 {
		return nil
	}
	first := off / s.chunk
	last := (off + n - 1) / s.chunk
	for c := first; c <= last; c++ {
		if err := s.ensureChunk(c); err != nil {
			return err
		}
	}
	return nil
}

// ReadAt fetches the covering chunks first, then reads from disk.
// Unfetchable ranges error — never zeros.
func (s *mediaStream) ReadAt(p []byte, off int64) (int, error) {
	if off < 0 {
		return 0, errors.New("stream: negative offset")
	}
	if off >= s.size {
		return 0, io.EOF
	}
	need := int64(len(p))
	if remain := s.size - off; need > remain {
		need = remain // clamp: the tail read stops at EOF
	}
	if err := s.ensure(off, need); err != nil {
		return 0, err // no partial zeros served
	}
	n, err := s.f.ReadAt(p[:need], off)
	if err != nil {
		return n, err
	}
	if int64(n) < int64(len(p)) {
		return n, io.EOF // asked past the end of the media
	}
	return n, nil
}

// Close releases the file handle. The sparse file itself stays on disk
// (it is either mid-download cache or the promoted completed file).
func (s *mediaStream) Close() error {
	s.mu.Lock()
	f := s.f
	s.f = nil
	s.mu.Unlock()
	if f == nil {
		return nil
	}
	return f.Close()
}

// mediaRow is the subset of the media table streaming needs.
type mediaRow struct {
	fileName   string
	remoteRef  string
	mimeType   string
	extra      string
	fileSize   int64
	downloadSt int
	localPath  string
}

func (e *Engine) loadMediaRow(accountID, chatID, msgID string, seq int) (*mediaRow, error) {
	var r mediaRow
	err := e.db.QueryRow(
		`SELECT COALESCE(remote_ref,''), COALESCE(file_name,''), COALESCE(mime_type,''),
		        COALESCE(extra,''), COALESCE(file_size,0), download_state, COALESCE(local_path,'')
		 FROM media WHERE account_id=? AND chat_id=? AND msg_id=? AND seq=?`,
		accountID, chatID, msgID, seq).
		Scan(&r.remoteRef, &r.fileName, &r.mimeType, &r.extra, &r.fileSize, &r.downloadSt, &r.localPath)
	if err != nil {
		return nil, fmt.Errorf("media ref not found: %w", err)
	}
	return &r, nil
}

// openMediaStream builds the streaming reader for an already-resolved
// source: canonical path (executeDownload's), completion promotion into
// the row, and the download_complete event — so the rest of the cache
// system cannot tell how the file arrived.
func (e *Engine) openMediaStream(accountID, chatID, msgID string, seq int, src partSource) (*mediaStream, int64, error) {
	r, err := e.loadMediaRow(accountID, chatID, msgID, seq)
	if err != nil {
		return nil, 0, err
	}
	if r.fileSize <= 0 {
		return nil, 0, fmt.Errorf("streaming: unknown file size")
	}
	if src == nil {
		return nil, 0, ErrNoRangedRead
	}

	// Same canonical path executeDownload writes (media.go executeDownload).
	dir := filepath.Join(e.mediaDir, accountID, "full")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, 0, err
	}
	ext := filepath.Ext(r.fileName)
	if ext == "" {
		ext = ".bin"
	}
	path := filepath.Join(dir, msgID+"_"+fmt.Sprint(seq)+ext)

	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o644)
	if err != nil {
		return nil, 0, err
	}
	ref := cores.FileRef{
		ID:       r.remoteRef,
		Name:     r.fileName,
		MimeType: r.mimeType,
		Extra:    r.extra,
	}
	size := r.fileSize
	onDone := func() {
		now := time.Now().UnixMilli()
		e.db.Exec(
			`UPDATE media SET local_path=?, download_state=?, last_accessed=?
			 WHERE account_id=? AND chat_id=? AND msg_id=? AND seq=?`,
			path, DownloadComplete, now, accountID, chatID, msgID, seq)
		e.emitEvent(EventDownloadComplete, accountID, DownloadCompleteEvent{
			AccountID: accountID,
			ChatID:    chatID,
			MsgID:     msgID,
			Seq:       seq,
			LocalPath: path,
		})
	}
	s, err := newMediaStream(f, size, streamChunk, src, ref, onDone)
	if err != nil {
		return nil, 0, err
	}
	return s, size, nil
}

// OpenMediaStream returns a reader over the media: the completed file
// straight from disk when it exists (fast path — no core needed), or a
// fetch-on-read stream that downloads only what the reader touches and
// promotes itself to a completed download at the same canonical path.
// ErrNoRangedRead means the caller should keep the download-then-play
// path.
func (e *Engine) OpenMediaStream(accountID, chatID, msgID string, seq int) (MediaReader, int64, error) {
	r, err := e.loadMediaRow(accountID, chatID, msgID, seq)
	if err != nil {
		return nil, 0, err
	}
	if r.downloadSt == DownloadComplete && r.localPath != "" {
		if f, oerr := os.Open(r.localPath); oerr == nil {
			return f, r.fileSize, nil
		}
		// Row says complete but the file was evicted: fall through and
		// refetch — honest recovery, not a phantom path.
	}

	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, 0, ErrNoRangedRead
	}
	src, err := resolveStreamSource(acc.Core)
	if err != nil {
		return nil, 0, err
	}
	// Streaming takes over this file's write path: cancel any queued or
	// active full download so two writers never race on one sparse file
	// (the stream finishes the same file the downloader would have).
	if e.media != nil {
		e.media.Cancel(accountID, chatID, msgID, seq)
	}
	return e.openMediaStream(accountID, chatID, msgID, seq, src)
}
