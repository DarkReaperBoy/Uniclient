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

var ErrNoRangedRead = errors.New("streaming: core cannot read byte ranges")

var ErrStreamBusy = errors.New("streaming: download already in progress")

var ErrStreamActive = errors.New("streaming: file is being saved by playback")

const streamChunk = 512 << 10

type partSource interface {
	ReadFilePart(fileRef cores.FileRef, offset, limit int64) ([]byte, error)
}

func ResolveStreamSource(core any) (partSource, error) {
	if core == nil {
		return nil, ErrNoRangedRead
	}
	if ps, ok := core.(partSource); ok {
		return ps, nil
	}
	return nil, ErrNoRangedRead
}

type MediaReader interface {
	io.ReaderAt
	io.Closer
}

type MediaStream struct {
	mu       sync.Mutex
	f        *os.File
	size     int64
	chunk    int64
	have     []bool
	src      partSource
	ref      cores.FileRef
	got      int64
	done     bool
	onDone   func()
	fetching map[int64]chan struct{}
	onClose  func()
}

func NewMediaStream(f *os.File, size, chunk int64, src partSource, ref cores.FileRef, onDone func()) (*MediaStream, error) {
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
	return &MediaStream{
		f:        f,
		size:     size,
		chunk:    chunk,
		have:     make([]bool, (size+chunk-1)/chunk),
		src:      src,
		ref:      ref,
		onDone:   onDone,
		fetching: make(map[int64]chan struct{}),
	}, nil
}

func (s *MediaStream) Size() int64 { return s.size }

func (s *MediaStream) Fetched() int64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.got
}

func (s *MediaStream) finishFetchLocked(c int64) {
	if ch, ok := s.fetching[c]; ok {
		delete(s.fetching, c)
		close(ch)
	}
}

func (s *MediaStream) ensureChunk(c int64) error {
	var (
		off, want int64
		src       partSource
		ref       cores.FileRef
	)
	for {
		s.mu.Lock()
		if c < 0 || c >= int64(len(s.have)) {
			s.mu.Unlock()
			return fmt.Errorf("stream: chunk %d out of range", c)
		}
		if s.have[c] {
			s.mu.Unlock()
			return nil
		}
		if busy, ok := s.fetching[c]; ok {
			s.mu.Unlock()
			<-busy
			continue
		}
		s.fetching[c] = make(chan struct{})
		off = c * s.chunk
		want = s.chunk
		if rem := s.size - off; rem < want {
			want = rem
		}
		src, ref = s.src, s.ref
		s.mu.Unlock()
		break
	}

	data, err := src.ReadFilePart(ref, off, want)
	if err != nil {
		s.mu.Lock()
		s.finishFetchLocked(c)
		s.mu.Unlock()
		return fmt.Errorf("stream: fetch chunk %d: %w", c, err)
	}
	if int64(len(data)) != want {
		s.mu.Lock()
		s.finishFetchLocked(c)
		s.mu.Unlock()
		return fmt.Errorf("stream: chunk %d: got %d bytes, want %d", c, len(data), want)
	}

	s.mu.Lock()
	n, err := s.f.WriteAt(data, off)
	if err == nil && int64(n) != want {
		err = io.ErrShortWrite
	}
	if err != nil {
		s.finishFetchLocked(c)
		s.mu.Unlock()
		return fmt.Errorf("stream: cache chunk %d: %w", c, err)
	}
	if !s.have[c] {
		s.have[c] = true
		s.got += want
	}
	justDone := false
	if !s.done {
		allPresent := true
		for _, ok := range s.have {
			if !ok {
				allPresent = false
				break
			}
		}
		if allPresent {
			s.done = true
			justDone = true
		}
	}
	s.finishFetchLocked(c)
	cb := s.onDone
	if justDone {
		s.onDone = nil
	}
	s.mu.Unlock()

	if justDone && cb != nil {
		cb()
	}
	return nil
}

func (s *MediaStream) ensure(off, n int64) error {
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

func (s *MediaStream) ReadAt(p []byte, off int64) (int, error) {
	if off < 0 {
		return 0, errors.New("stream: negative offset")
	}
	if off >= s.size {
		return 0, io.EOF
	}
	need := int64(len(p))
	if remain := s.size - off; need > remain {
		need = remain
	}
	if err := s.ensure(off, need); err != nil {
		return 0, err
	}
	n, err := s.f.ReadAt(p[:need], off)
	if err != nil {
		return n, err
	}
	if int64(n) < int64(len(p)) {
		return n, io.EOF
	}
	return n, nil
}

func (s *MediaStream) Close() error {
	s.mu.Lock()
	f := s.f
	s.f = nil
	cb := s.onClose
	s.onClose = nil
	s.mu.Unlock()
	if cb != nil {
		cb()
	}
	if f == nil {
		return nil
	}
	return f.Close()
}

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

func (e *Engine) openMediaStream(accountID, chatID, msgID string, seq int, src partSource) (*MediaStream, string, int64, error) {
	r, err := e.loadMediaRow(accountID, chatID, msgID, seq)
	if err != nil {
		return nil, "", 0, err
	}
	if r.fileSize <= 0 {
		return nil, "", 0, fmt.Errorf("streaming: unknown file size")
	}
	if src == nil {
		return nil, "", 0, ErrNoRangedRead
	}

	dir := filepath.Join(e.mediaDir, SafePathSegment(accountID), "full")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, "", 0, err
	}
	ext := filepath.Ext(r.fileName)
	if ext == "" {
		ext = ".bin"
	}
	path := filepath.Join(dir, SafePathSegment(msgID)+"_"+fmt.Sprint(seq)+ext)

	key := MediaGuardKey(accountID, chatID, msgID, seq)
	if !e.ClaimStream(key) {
		return nil, "", 0, ErrStreamBusy
	}
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o644)
	if err != nil {
		e.releaseStream(key)
		return nil, "", 0, err
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
	s, err := NewMediaStream(f, size, streamChunk, src, ref, onDone)
	if err != nil {
		e.releaseStream(key)
		return nil, "", 0, err
	}
	s.onClose = func() { e.releaseStream(key) }
	return s, path, size, nil
}

func (e *Engine) OpenMediaStream(accountID, chatID, msgID string, seq int) (MediaReader, int64, string, error) {
	r, err := e.loadMediaRow(accountID, chatID, msgID, seq)
	if err != nil {
		return nil, 0, "", err
	}
	if r.downloadSt == DownloadComplete && r.localPath != "" {
		if f, oerr := os.Open(r.localPath); oerr == nil {
			return f, r.fileSize, r.localPath, nil
		}
	}

	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, 0, "", ErrNoRangedRead
	}
	src, err := ResolveStreamSource(acc.Core)
	if err != nil {
		return nil, 0, "", err
	}
	if e.media != nil {
		e.media.Cancel(accountID, chatID, msgID, seq)
	}
	s, path, size, err := e.openMediaStream(accountID, chatID, msgID, seq, src)
	if err != nil {
		return nil, 0, "", err
	}
	return s, size, path, nil
}
