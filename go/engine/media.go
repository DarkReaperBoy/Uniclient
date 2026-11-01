package engine

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"uniclient/cores"
)

type DownloadJob struct {
	AccountID string
	ChatID    string
	MsgID     string
	Seq       int
	RemoteRef string
	FileName  string
	MimeType  string
	Extra     string
	Priority  int
	cancelFn  context.CancelFunc
}

type MediaManager struct {
	engine *Engine

	mu      sync.Mutex
	queue   []*DownloadJob
	active  int
	maxConc int
	wg      sync.WaitGroup
	notify  chan struct{}
}

func NewMediaManager(e *Engine) *MediaManager {
	mm := &MediaManager{
		engine:  e,
		maxConc: 10,
		notify:  make(chan struct{}, 1),
	}
	return mm
}

func (mm *MediaManager) Start(ctx context.Context) {
	mm.wg.Add(1)
	go func() {
		defer mm.wg.Done()
		for {
			select {
			case <-ctx.Done():
				return
			case <-mm.notify:
				mm.processQueue()
			}
		}
	}()
}

func (mm *MediaManager) Stop() {
	mm.wg.Wait()
}

func (mm *MediaManager) Enqueue(job *DownloadJob) {
	mm.mu.Lock()
	defer mm.mu.Unlock()

	inserted := false
	for i, j := range mm.queue {
		if job.Priority < j.Priority {
			mm.queue = append(mm.queue[:i+1], mm.queue[i:]...)
			mm.queue[i] = job
			inserted = true
			break
		}
	}
	if !inserted {
		mm.queue = append(mm.queue, job)
	}

	select {
	case mm.notify <- struct{}{}:
	default:
	}
}

func (mm *MediaManager) Cancel(accountID, chatID, msgID string, seq int) {
	mm.mu.Lock()
	defer mm.mu.Unlock()

	for i, j := range mm.queue {
		if j.AccountID == accountID && j.ChatID == chatID && j.MsgID == msgID && j.Seq == seq {
			if j.cancelFn != nil {
				j.cancelFn()
			}
			mm.queue = append(mm.queue[:i], mm.queue[i+1:]...)
			return
		}
	}
}

func (mm *MediaManager) processQueue() {
	for {
		mm.mu.Lock()
		if mm.active >= mm.maxConc || len(mm.queue) == 0 {
			mm.mu.Unlock()
			return
		}
		job := mm.queue[0]
		mm.queue = mm.queue[1:]
		mm.active++
		mm.mu.Unlock()

		mm.wg.Add(1)
		go func() {
			defer mm.wg.Done()
			mm.executeDownload(job)
			mm.mu.Lock()
			mm.active--
			mm.mu.Unlock()
			select {
			case mm.notify <- struct{}{}:
			default:
			}
		}()
	}
}

func (mm *MediaManager) executeDownload(job *DownloadJob) {
	e := mm.engine

	acc, ok := e.getAccount(job.AccountID)
	if !ok || acc.Core == nil {
		return
	}

	key := MediaGuardKey(job.AccountID, job.ChatID, job.MsgID, job.Seq)
	if !e.ClaimDownload(key) {
		return
	}
	defer e.ReleaseDownload(key)

	dir := filepath.Join(e.mediaDir, job.AccountID, "full")
	os.MkdirAll(dir, 0o755)

	ext := filepath.Ext(job.FileName)
	if ext == "" {
		ext = ".bin"
	}
	localPath := filepath.Join(dir, SafePathSegment(job.MsgID)+"_"+fmt.Sprint(job.Seq)+ext)

	e.db.Exec(
		"UPDATE media SET download_state = ? WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = ?",
		DownloadInProgress, job.AccountID, job.ChatID, job.MsgID, job.Seq)

	ref := cores.FileRef{
		ID:       job.RemoteRef,
		Name:     job.FileName,
		MimeType: job.MimeType,
		Extra:    job.Extra,
	}

	lastProgress := time.Now()
	err := acc.Core.DownloadFile(ref, localPath, func(recv, total int64) {
		if time.Since(lastProgress) < 100*time.Millisecond {
			return
		}
		lastProgress = time.Now()
		e.emitEvent(EventDownloadProgress, job.AccountID, DownloadProgressEvent{
			AccountID:  job.AccountID,
			ChatID:     job.ChatID,
			MsgID:      job.MsgID,
			Seq:        job.Seq,
			BytesRecv:  recv,
			BytesTotal: total,
		})
	})

	if err != nil {
		os.Remove(localPath)
		e.db.Exec(
			"UPDATE media SET download_state = ? WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = ?",
			DownloadFailed, job.AccountID, job.ChatID, job.MsgID, job.Seq)
		e.emitEvent(EventDownloadFailed, job.AccountID, DownloadFailedEvent{
			AccountID: job.AccountID,
			ChatID:    job.ChatID,
			MsgID:     job.MsgID,
			Seq:       job.Seq,
			Err:       err.Error(),
		})
		return
	}

	now := time.Now().UnixMilli()
	e.db.Exec(
		`UPDATE media SET local_path = ?, download_state = ?, last_accessed = ?
		 WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = ?`,
		localPath, DownloadComplete, now, job.AccountID, job.ChatID, job.MsgID, job.Seq)

	e.emitEvent(EventDownloadComplete, job.AccountID, DownloadCompleteEvent{
		AccountID: job.AccountID,
		ChatID:    job.ChatID,
		MsgID:     job.MsgID,
		Seq:       job.Seq,
		LocalPath: localPath,
	})

	mm.maybeEvict()
}

type mediaGuard struct {
	streams int
	dl      bool
}

func MediaGuardKey(accountID, chatID, msgID string, seq int) string {
	return accountID + "|" + chatID + "|" + msgID + "|" + fmt.Sprint(seq)
}

func (e *Engine) ClaimStream(key string) bool {
	e.guardMu.Lock()
	defer e.guardMu.Unlock()
	if e.guards == nil {
		e.guards = make(map[string]*mediaGuard)
	}
	g := e.guards[key]
	if g == nil {
		g = &mediaGuard{}
		e.guards[key] = g
	}
	if g.dl {
		return false
	}
	g.streams++
	return true
}

func (e *Engine) releaseStream(key string) {
	e.guardMu.Lock()
	defer e.guardMu.Unlock()
	if g := e.guards[key]; g != nil {
		g.streams--
		if g.streams <= 0 && !g.dl {
			delete(e.guards, key)
		}
	}
}

func (e *Engine) ClaimDownload(key string) bool {
	e.guardMu.Lock()
	defer e.guardMu.Unlock()
	if e.guards == nil {
		e.guards = make(map[string]*mediaGuard)
	}
	g := e.guards[key]
	if g == nil {
		g = &mediaGuard{}
		e.guards[key] = g
	}
	if g.streams > 0 || g.dl {
		return false
	}
	g.dl = true
	return true
}

func (e *Engine) ReleaseDownload(key string) {
	e.guardMu.Lock()
	defer e.guardMu.Unlock()
	if g := e.guards[key]; g != nil && g.dl {
		g.dl = false
		if g.streams <= 0 {
			delete(e.guards, key)
		}
	}
}

func (e *Engine) streamActive(key string) bool {
	e.guardMu.Lock()
	defer e.guardMu.Unlock()
	g := e.guards[key]
	return g != nil && g.streams > 0
}

func (e *Engine) RequestDownload(accountID, chatID, msgID string, seq, priority int) error {
	var remoteRef, fileName, mimeType, extra sql.NullString
	var state int
	var localPath sql.NullString
	err := e.db.QueryRow(
		"SELECT remote_ref, file_name, mime_type, extra, download_state, COALESCE(local_path,'') FROM media WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = ?",
		accountID, chatID, msgID, seq).Scan(&remoteRef, &fileName, &mimeType, &extra, &state, &localPath)
	if err != nil {
		return fmt.Errorf("media ref not found: %w", err)
	}
	if state == DownloadComplete && localPath.String != "" {
		if _, serr := os.Stat(localPath.String); serr == nil {
			e.emitEvent(EventDownloadComplete, accountID, DownloadCompleteEvent{
				AccountID: accountID, ChatID: chatID, MsgID: msgID, Seq: seq,
				LocalPath: localPath.String,
			})
			return nil
		}
	}
	if e.streamActive(MediaGuardKey(accountID, chatID, msgID, seq)) {
		return ErrStreamActive
	}

	if e.media == nil {
		return fmt.Errorf("media manager not initialized")
	}

	e.media.Enqueue(&DownloadJob{
		AccountID: accountID,
		ChatID:    chatID,
		MsgID:     msgID,
		Seq:       seq,
		RemoteRef: remoteRef.String,
		FileName:  fileName.String,
		MimeType:  mimeType.String,
		Extra:     extra.String,
		Priority:  priority,
	})
	return nil
}

func (e *Engine) CancelDownload(accountID, chatID, msgID string, seq int) {
	if e.media != nil {
		e.media.Cancel(accountID, chatID, msgID, seq)
	}
}

func (e *Engine) GetCacheSize() (int64, error) {
	var total sql.NullInt64
	err := e.db.QueryRow(
		"SELECT COALESCE(SUM(file_size), 0) FROM media WHERE download_state = ?",
		DownloadComplete).Scan(&total)
	if err != nil {
		return 0, err
	}
	return total.Int64, nil
}

func (e *Engine) GetCacheSizesByTag(accountID string) ([6]int64, error) {
	var sizes [6]int64

	tagSum := func(types []int) (int64, error) {
		placeholders := make([]string, len(types))
		args := make([]interface{}, 0, len(types)+2)
		args = append(args, DownloadComplete)
		for i, t := range types {
			placeholders[i] = "?"
			args = append(args, t)
		}
		q := "SELECT COALESCE(SUM(file_size), 0) FROM media WHERE download_state = ? AND media_type IN (" + strings.Join(placeholders, ",") + ")"
		if accountID != "" {
			q += " AND account_id = ?"
			args = append(args, accountID)
		}
		var total sql.NullInt64
		if err := e.db.QueryRow(q, args...).Scan(&total); err != nil {
			return 0, err
		}
		return total.Int64, nil
	}

	var categorized int64
	for tag := 0; tag < 5; tag++ {
		s, err := tagSum(mediaTypesForTag(tag))
		if err != nil {
			return sizes, err
		}
		sizes[tag] = s
		categorized += s
	}

	q := "SELECT COALESCE(SUM(file_size), 0) FROM media WHERE download_state = ?"
	args := []interface{}{DownloadComplete}
	if accountID != "" {
		q += " AND account_id = ?"
		args = append(args, accountID)
	}
	var full sql.NullInt64
	if err := e.db.QueryRow(q, args...).Scan(&full); err != nil {
		return sizes, err
	}
	sizes[5] = full.Int64 - categorized
	if sizes[5] < 0 {
		sizes[5] = 0
	}
	return sizes, nil
}

func (e *Engine) ClearCache(accountID string) error {
	var rows *sql.Rows
	var err error
	if accountID != "" {
		rows, err = e.db.Query(
			"SELECT local_path FROM media WHERE account_id = ? AND local_path IS NOT NULL",
			accountID)
	} else {
		rows, err = e.db.Query(
			"SELECT local_path FROM media WHERE local_path IS NOT NULL")
	}
	if err != nil {
		return err
	}
	defer rows.Close()

	for rows.Next() {
		var path string
		rows.Scan(&path)
		os.Remove(path)
	}

	if accountID != "" {
		e.db.Exec("UPDATE media SET local_path = NULL, download_state = 0 WHERE account_id = ?", accountID)
	} else {
		e.db.Exec("UPDATE media SET local_path = NULL, download_state = 0")
	}
	return nil
}

func mediaTypesForTag(tag int) []int {
	switch tag {
	case 0:
		return []int{MediaImage}
	case 1:
		return []int{MediaSticker}
	case 2:
		return []int{MediaVoice}
	case 3:
		return []int{MediaVideoNote}
	case 4:
		return []int{MediaGIF}
	case 5:
		return []int{MediaVideo, MediaAudio, MediaFile}
	default:
		return nil
	}
}

func (e *Engine) ClearCacheByTag(accountID string, tag int) error {
	types := mediaTypesForTag(tag)
	if len(types) == 0 {
		return nil
	}

	placeholders := make([]string, len(types))
	args := make([]interface{}, 0, len(types)+1)
	for i, t := range types {
		placeholders[i] = "?"
		args = append(args, t)
	}
	inClause := strings.Join(placeholders, ",")

	selectQ := "SELECT local_path FROM media WHERE local_path IS NOT NULL AND media_type IN (" + inClause + ")"
	updateQ := "UPDATE media SET local_path = NULL, download_state = 0 WHERE media_type IN (" + inClause + ")"
	if accountID != "" {
		selectQ += " AND account_id = ?"
		updateQ += " AND account_id = ?"
		args = append(args, accountID)
	}

	rows, err := e.db.Query(selectQ, args...)
	if err != nil {
		return err
	}
	var paths []string
	for rows.Next() {
		var path string
		rows.Scan(&path)
		paths = append(paths, path)
	}
	rows.Close()

	for _, path := range paths {
		os.Remove(path)
	}
	e.db.Exec(updateQ, args...)
	return nil
}

func (mm *MediaManager) maybeEvict() {
	mm.evictExpired()
	mm.evictBigMedia()
	mm.evictTotal()
}

type mediaVictim struct {
	accID, chatID, msgID, localPath string
	seq                             int
	fileSize                        int64
}

func (e *Engine) isThumb(accID, localPath string) bool {
	return filepath.Dir(localPath) == filepath.Join(e.mediaDir, SafePathSegment(accID), "thumb")
}

func (e *Engine) dropVictim(v mediaVictim) {
	os.Remove(v.localPath)
	e.db.Exec(
		"UPDATE media SET local_path = NULL, download_state = 0 WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = ?",
		v.accID, v.chatID, v.msgID, v.seq)
}

var bigMediaTypes = []int{MediaVideo, MediaFile, MediaAudio, MediaVoice, MediaVideoNote, MediaGIF}

func (mm *MediaManager) evictExpired() {
	e := mm.engine
	days := e.localStorageTimeDays
	if days <= 0 {
		return
	}
	cutoff := time.Now().Add(-time.Duration(days) * 24 * time.Hour).UnixMilli()
	rows, err := e.db.Query(
		`SELECT account_id, chat_id, msg_id, seq, local_path
		 FROM media
		 WHERE local_path IS NOT NULL AND download_state = ? AND last_accessed < ?`,
		DownloadComplete, cutoff)
	if err != nil {
		return
	}
	var victims []mediaVictim
	for rows.Next() {
		var v mediaVictim
		rows.Scan(&v.accID, &v.chatID, &v.msgID, &v.seq, &v.localPath)
		victims = append(victims, v)
	}
	rows.Close()

	for _, v := range victims {
		if e.isThumb(v.accID, v.localPath) {
			continue
		}
		e.dropVictim(v)
	}
}

func (mm *MediaManager) evictBigMedia() {
	e := mm.engine
	if e.localStorageMediaMB <= 0 {
		return
	}
	limit := int64(e.localStorageMediaMB) * 1024 * 1024

	placeholders := make([]string, len(bigMediaTypes))
	typeArgs := make([]interface{}, len(bigMediaTypes))
	for i, t := range bigMediaTypes {
		placeholders[i] = "?"
		typeArgs[i] = t
	}
	inClause := strings.Join(placeholders, ",")

	var size sql.NullInt64
	e.db.QueryRow(
		"SELECT COALESCE(SUM(file_size),0) FROM media WHERE download_state = ? AND local_path IS NOT NULL AND media_type IN ("+inClause+")",
		append([]interface{}{DownloadComplete}, typeArgs...)...).Scan(&size)
	if size.Int64 <= limit {
		return
	}

	rows, err := e.db.Query(
		"SELECT account_id, chat_id, msg_id, seq, local_path, file_size FROM media WHERE local_path IS NOT NULL AND download_state = ? AND media_type IN ("+inClause+") ORDER BY last_accessed ASC",
		append([]interface{}{DownloadComplete}, typeArgs...)...)
	if err != nil {
		return
	}
	var victims []mediaVictim
	for rows.Next() {
		var v mediaVictim
		rows.Scan(&v.accID, &v.chatID, &v.msgID, &v.seq, &v.localPath, &v.fileSize)
		victims = append(victims, v)
	}
	rows.Close()

	cur := size.Int64
	for _, v := range victims {
		if cur <= limit {
			break
		}
		if e.isThumb(v.accID, v.localPath) {
			continue
		}
		e.dropVictim(v)
		cur -= v.fileSize
	}
}

func (mm *MediaManager) evictTotal() {
	e := mm.engine
	if e.maxCache <= 0 {
		return
	}
	size, _ := e.GetCacheSize()
	if size <= e.maxCache {
		return
	}

	rows, err := e.db.Query(
		`SELECT account_id, chat_id, msg_id, seq, local_path, file_size
		 FROM media
		 WHERE local_path IS NOT NULL AND download_state = ?
		 ORDER BY last_accessed ASC`,
		DownloadComplete)
	if err != nil {
		return
	}
	var victims []mediaVictim
	for rows.Next() {
		var v mediaVictim
		rows.Scan(&v.accID, &v.chatID, &v.msgID, &v.seq, &v.localPath, &v.fileSize)
		victims = append(victims, v)
	}
	rows.Close()

	for _, v := range victims {
		if size <= e.maxCache {
			break
		}
		if e.isThumb(v.accID, v.localPath) {
			continue
		}
		e.dropVictim(v)
		size -= v.fileSize
	}
}
