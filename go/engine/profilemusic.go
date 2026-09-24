package engine

// profilemusic.go — slice 206: profile music ("saved music", tdesktop Aug
// 2026). Songs pinned on user profiles: a per-(account, peer) ordered
// playlist cache fed by users.getSavedMusic, own-playlist mutations through
// account.saveMusic (add / move-after / unsave) with cache + event updates,
// the own-ID set (hash-gated account.getSavedMusicIDs) behind the
// bubble-menu gate, and track playback through the shared in-app player
// (download via the core's FileRef path, then PlayMedia keyed
// (account, "profilemusic", docID)).

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"uniclient/cores"
)

// ProfileMusicFetcher is the server-side playlist fetch (users.getSavedMusic).
type ProfileMusicFetcher interface {
	GetProfileMusic(peerID string) ([]cores.MusicTrackInfo, int, error)
}

// ProfileMusicSaver is the own-playlist mutation surface (account.saveMusic).
type ProfileMusicSaver interface {
	SaveProfileMusicDoc(track, after cores.MusicTrackInfo, unsave bool) error
}

// OwnSavedMusicIDsFetcher is the own-playlist ID list (account.getSavedMusicIDs).
type OwnSavedMusicIDsFetcher interface {
	GetOwnSavedMusicIDs(hash int64) ([]string, bool, error)
}

// MusicTrack is the engine-side cached profile-music track (json-shaped
// for the GUI).
type MusicTrack struct {
	DocID      string `json:"doc_id"`
	Title      string `json:"title,omitempty"`
	Performer  string `json:"performer,omitempty"`
	Duration   int    `json:"duration,omitempty"`
	Size       int64  `json:"size,omitempty"`
	MimeType   string `json:"mime_type,omitempty"`
	FileName   string `json:"file_name,omitempty"`
	AccessHash int64  `json:"access_hash,omitempty"`
	FileRefB64 string `json:"file_ref,omitempty"`
	Position   int    `json:"position"`
}

// ProfileMusicSupported reports whether the account's core exposes the
// profile-music surface (Telegram today).
func (e *Engine) ProfileMusicSupported(accountID string) bool {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return false
	}
	_, ok = acc.Core.(ProfileMusicFetcher)
	return ok
}

func (e *Engine) profileMusicFetcher(accountID string) (ProfileMusicFetcher, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	f, ok := acc.Core.(ProfileMusicFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support profile music")
	}
	return f, nil
}

// GetProfileMusic returns the peer's cached playlist in order. A cold
// cache is fed by one server fetch before returning (first open shows real
// rows); warm caches read locally — freshness rides the
// profile-music-changed events that follow mutations.
func (e *Engine) GetProfileMusic(accountID, peerID string) ([]MusicTrack, error) {
	if tracks, ok := e.readProfileMusic(accountID, peerID); ok {
		return tracks, nil
	}
	f, err := e.profileMusicFetcher(accountID)
	if err != nil {
		return nil, err
	}
	info, _, err := f.GetProfileMusic(peerID)
	if err != nil {
		// Empty-but-known (user with no music) must stay an honest empty
		// state, not an error; only real failures propagate.
		return nil, err
	}
	e.storeProfileMusic(accountID, peerID, info)
	return e.readProfileMusicRows(accountID, peerID)
}

func (e *Engine) readProfileMusicRows(accountID, peerID string) ([]MusicTrack, error) {
	rows, err := e.db.Query(
		`SELECT doc_id, title, performer, duration, size, mime_type, file_name, access_hash, file_ref, position
                 FROM profile_music WHERE account_id = ? AND peer_id = ?
                 ORDER BY position ASC`, accountID, peerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var tracks []MusicTrack
	for rows.Next() {
		var t MusicTrack
		if err := rows.Scan(&t.DocID, &t.Title, &t.Performer, &t.Duration, &t.Size, &t.MimeType, &t.FileName, &t.AccessHash, &t.FileRefB64, &t.Position); err != nil {
			return nil, err
		}
		tracks = append(tracks, t)
	}
	return tracks, rows.Err()
}

// readProfileMusic reports ok=false only when the peer has NO cached rows
// at all (never fetched).
func (e *Engine) readProfileMusic(accountID, peerID string) ([]MusicTrack, bool) {
	tracks, err := e.readProfileMusicRows(accountID, peerID)
	if err != nil {
		return nil, false
	}
	return tracks, tracks != nil
}

func (e *Engine) storeProfileMusic(accountID, peerID string, info []cores.MusicTrackInfo) {
	now := time.Now().Unix()
	tx, err := e.db.Begin()
	if err != nil {
		return
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`DELETE FROM profile_music WHERE account_id = ? AND peer_id = ?`, accountID, peerID); err != nil {
		return
	}
	for i, tr := range info {
		if _, err := tx.Exec(
			`INSERT INTO profile_music (account_id, peer_id, doc_id, position, access_hash, file_ref, title, performer, duration, size, mime_type, file_name, updated_at)
                         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)`,
			accountID, peerID, tr.DocID, i, tr.AccessHash, tr.FileRefB64, tr.Title, tr.Performer, tr.Duration, tr.Size, tr.MimeType, tr.FileName, now); err != nil {
			return
		}
	}
	if err := tx.Commit(); err != nil {
		return
	}
}

func (e *Engine) profileMusicSelfID(accountID string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", fmt.Errorf("account not found: %s", accountID)
	}
	type selfIDer interface{ SelfUserID() string }
	if s, ok := acc.Core.(selfIDer); ok {
		if sid := s.SelfUserID(); sid != "" {
			return sid, nil
		}
	}
	return "", fmt.Errorf("account has no self peer ID")
}

// SaveToProfileMusic adds a track to the OWN playlist (plain
// account.saveMusic — an already-saved song moves to the top), then
// refetches the own playlist + ID set and emits the change event.
func (e *Engine) SaveToProfileMusic(accountID string, track MusicTrack) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	saver, ok := acc.Core.(ProfileMusicSaver)
	if !ok {
		return fmt.Errorf("platform does not support profile music")
	}
	if err := saver.SaveProfileMusicDoc(trackInfoOf(track), cores.MusicTrackInfo{}, false); err != nil {
		return err
	}
	e.refreshProfileMusicAfterMutation(accountID)
	return nil
}

// RemoveProfileMusic removes a track from the OWN playlist.
func (e *Engine) RemoveProfileMusic(accountID, docID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	saver, ok := acc.Core.(ProfileMusicSaver)
	if !ok {
		return fmt.Errorf("platform does not support profile music")
	}
	// The cache row carries the download reference the RPC needs.
	track, err := e.profileMusicTrackByDoc(accountID, docID)
	if err != nil {
		return err
	}
	if err := saver.SaveProfileMusicDoc(trackInfoOf(track), cores.MusicTrackInfo{}, true); err != nil {
		return err
	}
	e.refreshProfileMusicAfterMutation(accountID)
	return nil
}

// ReorderProfileMusic moves one own-playlist track right after another
// (account.saveMusic after_id). afterDocID "" = move to top.
func (e *Engine) ReorderProfileMusic(accountID, docID, afterDocID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	saver, ok := acc.Core.(ProfileMusicSaver)
	if !ok {
		return fmt.Errorf("platform does not support profile music")
	}
	selfID, err := e.profileMusicSelfID(accountID)
	if err != nil {
		return err
	}
	tracks, ok := e.readProfileMusic(accountID, selfID)
	if !ok {
		return fmt.Errorf("own playlist not loaded yet")
	}
	var track, after MusicTrack
	foundTrack, foundAfter := false, afterDocID == ""
	for _, t := range tracks {
		if t.DocID == docID {
			track, foundTrack = t, true
		}
		if afterDocID != "" && t.DocID == afterDocID {
			after, foundAfter = t, true
		}
	}
	if !foundTrack {
		return fmt.Errorf("track %s is not in the playlist", docID)
	}
	if !foundAfter {
		return fmt.Errorf("anchor %s is not in the playlist", afterDocID)
	}
	// Same-position no-op: the anchor is already the predecessor.
	for i, t := range tracks {
		if t.DocID == docID && i > 0 && tracks[i-1].DocID == afterDocID {
			return nil
		}
	}
	if err := saver.SaveProfileMusicDoc(trackInfoOf(track), trackInfoOf(after), false); err != nil {
		return err
	}
	e.refreshProfileMusicAfterMutation(accountID)
	return nil
}

// refreshProfileMusicAfterMutation re-syncs the own playlist + ID set and
// emits the change events (GUI reloads panels and the playlist view).
func (e *Engine) refreshProfileMusicAfterMutation(accountID string) {
	selfID, err := e.profileMusicSelfID(accountID)
	if err != nil {
		return
	}
	if f, err := e.profileMusicFetcher(accountID); err == nil {
		if info, _, err := f.GetProfileMusic(selfID); err == nil {
			e.storeProfileMusic(accountID, selfID, info)
		}
	}
	if _, err := e.RefreshOwnProfileMusic(accountID); err == nil {
		// RefreshOwnProfileMusic already emitted the event.
		return
	}
	e.emitEvent(EventProfileMusicChanged, accountID, ProfileMusicEvent{PeerID: selfID})
}

// profileMusicTrackByDoc finds one cached track by document ID (any peer).
func (e *Engine) profileMusicTrackByDoc(accountID, docID string) (MusicTrack, error) {
	var t MusicTrack
	err := e.db.QueryRow(
		`SELECT doc_id, title, performer, duration, size, mime_type, file_name, access_hash, file_ref, position
                 FROM profile_music WHERE account_id = ? AND doc_id = ? LIMIT 1`, accountID, docID).
		Scan(&t.DocID, &t.Title, &t.Performer, &t.Duration, &t.Size, &t.MimeType, &t.FileName, &t.AccessHash, &t.FileRefB64, &t.Position)
	if err == sql.ErrNoRows {
		return t, fmt.Errorf("track %s is not cached", docID)
	}
	return t, err
}

func trackInfoOf(t MusicTrack) cores.MusicTrackInfo {
	return cores.MusicTrackInfo{
		DocID:      t.DocID,
		AccessHash: t.AccessHash,
		FileRefB64: t.FileRefB64,
		Title:      t.Title,
		Performer:  t.Performer,
		Duration:   t.Duration,
		Size:       t.Size,
		MimeType:   t.MimeType,
		FileName:   t.FileName,
	}
}

// TrackFromMessage builds a MusicTrack from one cached audio message: the
// media row carries the document ID (remote_ref) + the download reference
// ("hash:base64ref" in extra), the message content the embedded tags. ok
// is false for messages without a usable audio document row.
func (e *Engine) TrackFromMessage(accountID, chatID, msgID string, seq int) (MusicTrack, bool) {
	var t MusicTrack
	var remoteRef, extra sql.NullString
	var fileName, mime sql.NullString
	var size sql.NullInt64
	var durMs sql.NullInt64
	err := e.db.QueryRow(
		`SELECT remote_ref, file_name, mime_type, file_size, duration_ms, extra
                 FROM media WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = ?`,
		accountID, chatID, msgID, seq).
		Scan(&remoteRef, &fileName, &mime, &size, &durMs, &extra)
	if err != nil || !remoteRef.Valid || remoteRef.String == "" {
		return t, false
	}
	t.DocID = remoteRef.String
	t.FileName = fileName.String
	t.MimeType = mime.String
	t.Size = size.Int64
	t.Duration = int(durMs.Int64 / 1000)
	t.FileRefB64 = ""
	t.AccessHash = 0
	if extra.Valid {
		// extra is "accessHash:base64FileRef" — split it in place.
		if i := indexByte(extra.String, ':'); i > 0 {
			t.AccessHash, _ = strconv.ParseInt(extra.String[:i], 10, 64)
			t.FileRefB64 = extra.String[i+1:]
		}
	}
	// Embedded tags ride on the cached message content.
	if raw, err := e.GetMessageRaw(accountID, chatID, msgID); err == nil {
		var msg struct {
			Extra map[string]interface{} `json:"extra"`
		}
		if json.Unmarshal(raw, &msg) == nil && msg.Extra != nil {
			if title, ok := msg.Extra["audio_title"].(string); ok {
				t.Title = title
			}
			if performer, ok := msg.Extra["audio_performer"].(string); ok {
				t.Performer = performer
			}
		}
	}
	return t, true
}

func indexByte(s string, b byte) int {
	for i := 0; i < len(s); i++ {
		if s[i] == b {
			return i
		}
	}
	return -1
}

// RefreshOwnProfileMusic re-reads the account's own saved-music ID set
// (hash-gated account.getSavedMusicIDs) and emits the change event.
func (e *Engine) RefreshOwnProfileMusic(accountID string) (map[string]bool, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	fetcher, ok := acc.Core.(OwnSavedMusicIDsFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support profile music")
	}
	e.ownMusicMu.Lock()
	if e.ownMusicIDs == nil {
		e.ownMusicIDs = map[string]map[string]bool{}
	}
	if e.ownMusicHash == nil {
		e.ownMusicHash = map[string]int64{}
	}
	hash := e.ownMusicHash[accountID]
	e.ownMusicMu.Unlock()

	ids, changed, err := fetcher.GetOwnSavedMusicIDs(hash)
	if err != nil {
		return nil, err
	}
	if changed {
		set := make(map[string]bool, len(ids))
		sum := int64(0)
		for _, id := range ids {
			set[id] = true
			if n, err := strconv.ParseInt(id, 10, 64); err == nil {
				sum += n
			}
		}
		e.ownMusicMu.Lock()
		e.ownMusicIDs[accountID] = set
		e.ownMusicHash[accountID] = sum
		e.ownMusicMu.Unlock()
	} else {
		e.ownMusicMu.Lock()
		set := e.ownMusicIDs[accountID]
		e.ownMusicMu.Unlock()
		return set, nil
	}
	var selfID string
	if sid, err := e.profileMusicSelfID(accountID); err == nil {
		selfID = sid
	}
	e.emitEvent(EventProfileMusicChanged, accountID, ProfileMusicEvent{PeerID: selfID})
	e.ownMusicMu.Lock()
	defer e.ownMusicMu.Unlock()
	return e.ownMusicIDs[accountID], nil
}

// OwnProfileMusicCached is the pure in-memory read for the bubble-menu
// gate (nil map = unknown, callers treat as absent).
func (e *Engine) OwnProfileMusicCached(accountID string) map[string]bool {
	e.ownMusicMu.Lock()
	defer e.ownMusicMu.Unlock()
	return e.ownMusicIDs[accountID]
}

// PlayProfileMusicTrack plays one cached track through the shared in-app
// player: download-once into the media cache (FileRef with the encoded
// access hash + file reference), then PlayMedia keyed
// (account, "profilemusic", docID).
func (e *Engine) PlayProfileMusicTrack(accountID, docID string) error {
	track, err := e.profileMusicTrackByDoc(accountID, docID)
	if err != nil {
		return err
	}
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	downloader, ok := acc.Core.(interface {
		DownloadFile(fileRef cores.FileRef, dest string, progress func(recv, total int64)) error
	})
	if !ok {
		return fmt.Errorf("platform cannot download profile music")
	}
	dir := filepath.Join(e.mediaDir, accountID, "full")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	ext := filepath.Ext(track.FileName)
	if ext == "" {
		ext = ".bin"
	}
	dest := filepath.Join(dir, "profilemusic_"+track.DocID+ext)
	if _, statErr := os.Stat(dest); statErr != nil {
		ref := cores.FileRef{
			ID:       track.DocID,
			Name:     track.FileName,
			MimeType: track.MimeType,
			Size:     track.Size,
			Extra:    strconv.FormatInt(track.AccessHash, 10) + ":" + track.FileRefB64,
		}
		if err := downloader.DownloadFile(ref, dest, nil); err != nil {
			return err
		}
	}
	return e.PlayMedia(accountID, "profilemusic", track.DocID, dest)
}

// ── slice 210: music attach box (saved-music source) ──────────────────────

// AudioDocumentSender is the optional core surface for sending a cloud
// audio document by reference (the music attach box's saved-music send
// path, tdesktop music_attach_box.cpp).
type AudioDocumentSender interface {
	SendAudioDocument(chatID string, track cores.MusicTrackInfo, caption string, silent bool, scheduleDate int) (*cores.Message, error)
}

// SavedMusicTracks returns the account's OWN saved-music playlist — the
// music attach box's source. Honest ErrNotSupported on platforms without
// the surface (the box shows only the file picker then).
func (e *Engine) SavedMusicTracks(accountID string) ([]MusicTrack, error) {
	if !e.ProfileMusicSupported(accountID) {
		return nil, cores.ErrNotSupported
	}
	selfID, err := e.profileMusicSelfID(accountID)
	if err != nil {
		return nil, err
	}
	return e.GetProfileMusic(accountID, selfID)
}

// SendSavedMusicTrack sends one saved-music track into a chat as a new
// audio message (caption rides the message; the attach box passes the
// composer's caption with the first track only).
func (e *Engine) SendSavedMusicTrack(accountID, chatID, docID, caption string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	sender, ok := acc.Core.(AudioDocumentSender)
	if !ok {
		return fmt.Errorf("%w: sending saved music", cores.ErrNotSupported)
	}
	track, err := e.profileMusicTrackByDoc(accountID, docID)
	if err != nil {
		return err
	}
	_, err = sender.SendAudioDocument(chatID, trackInfoOf(track), caption, false, 0)
	return err
}
