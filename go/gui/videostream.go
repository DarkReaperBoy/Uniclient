package gui

// videostream.go — slice 229: playback that STARTS before the file has
// fully downloaded (parity row 281, "streaming video in chat").
//
// The chain: engine.OpenMediaStream hands back a fetch-on-read sparse
// file (slice 228) → h264vid.ParseSeek reads only box headers + moov
// (streamsrc.go) → the picture decodes while chunks arrive → when the
// last chunk lands the row promotes to DownloadComplete and SOUND joins
// caught up to the picture's playhead (state.go → videoAudioPlayAt).
//
// Every failure falls back to the old download-then-play flow: no
// ranged read (other cores / no remote ref), or a container our
// decoder rejects (HEVC-in-MP4) → honest fallback, never a dead bubble
// (§1.10).

import (
	"time"

	"uniclient/engine"
)

// viewerMayStream is the viewer's cheap pre-filter: a video that is not
// local yet, in a container we can attempt (the real verdict comes from
// h264vid.ParseSeek — this only avoids asking the engine for a stream
// of something we would never play). The container check accepts the
// file-name extension (mirroring inAppVideoExt for the complete-file
// path) or an explicit video/mp4 mime, since a viewer item carries both.
// Pure — unit-tested.
func viewerMayStream(it engine.SharedMediaItem) bool {
	if it.LocalPath != "" || !viewerIsVideo(it) {
		return false
	}
	if inAppVideoExt(it.FileName) {
		return true
	}
	return it.MimeType == "video/mp4"
}

// streamJoinAt decides whether DownloadComplete should start SOUND for
// an active streamed picture, and at which offset. Guards (pure,
// unit-tested): there is a player, it is parsed and currently playing (a
// paused or stopped picture must not have sound start behind it), and it
// is streaming THIS exact path (the download-driven playOnDone flow,
// which owns its own audio start, is ordered before this call and must
// not be double-started). The offset WRAPS with a looping round note
// (the picture is mid-pass — sound must join the same phase) and refuses
// to start behind a viewer clip that already played through: orphan
// sound behind a frozen last frame would be fake playback (§1.10).
func streamJoinAt(st h264PlayerState, have bool, localPath string, elapsed time.Duration) (time.Duration, bool) {
	if !have || !st.parsed || !st.playing || st.path != localPath || st.video == nil {
		return 0, false
	}
	total := st.video.Total
	if total <= 0 {
		return 0, false
	}
	if st.loop {
		return elapsed % total, true
	}
	if elapsed >= total {
		return 0, false
	}
	return elapsed, true
}

// startStreamedVideoNote is the round-note tap's row-281 fast path:
// the tap plays the note from the ranged stream immediately instead of
// blocking on a full download (the stream IS the download — it
// promotes the row when its last chunk lands). False → caller runs the
// old wait-for-download flow unchanged.
func (a *App) startStreamedVideoNote(m *engine.CachedMessage) bool {
	if a.eng == nil || m == nil || m.MsgID == "" {
		return false
	}
	// Already playing or parsing this file → no second reader (every
	// duplicate open used to cost an fd nothing ever closed, slice 230).
	if st, ok := h264Players.peek(m.MsgID); ok && !st.failed && st.path != "" && (st.parsed || st.reading) {
		return true
	}
	r, size, path, err := a.eng.OpenMediaStream(m.AccountID, m.ChatID, m.MsgID, 0)
	if err != nil {
		return false // no ranged read, or a download owns the file: old flow
	}
	fallback := func() {
		// Parse rejected the bytes (e.g. HEVC-in-MP4): ensure() already
		// consumed our reader (ownership rule), so do exactly what the tap
		// would have done with no stream available.
		a.setPlayOnDone(m.AccountID, m.ChatID, m.MsgID, 0)
		go func() {
			if err := a.eng.RequestDownload(m.AccountID, m.ChatID, m.MsgID, 0, 0); err != nil {
				a.setToast("Download failed: " + err.Error())
			}
		}()
	}
	// Ownership: ensureH264StreamPlayer CONSUMES r on every path.
	return a.ensureH264StreamPlayer(m.MsgID, path, r, size, true, fallback)
}

// startStreamedViewerVideo is the viewer's row-281 fast path (loop=false:
// the viewer plays through, transport controls included — they act on
// the same player cache entry a downloaded clip would publish).
func (a *App) startStreamedViewerVideo(v *viewerState, it engine.SharedMediaItem) bool {
	if v == nil || a.eng == nil || !viewerMayStream(it) {
		return false
	}
	acct, chat, id := v.accountID, v.chatID, it.MsgID
	// Already playing or parsing this file → no second reader (slice 230).
	if st, ok := h264Players.peek(id); ok && !st.failed && st.path != "" && (st.parsed || st.reading) {
		return true
	}
	r, size, path, err := a.eng.OpenMediaStream(acct, chat, id, 0)
	if err != nil {
		return false
	}
	fallback := func() {
		// ensure() consumed the reader already (ownership rule).
		a.setOpenOnDone(acct, chat, id, 0)
		go func() {
			if err := a.eng.RequestDownload(acct, chat, id, 0, 0); err != nil {
				a.setToast("Download failed: " + err.Error())
			}
		}()
		a.setToast("Downloading video…")
	}
	// Ownership: ensureH264StreamPlayer CONSUMES r on every path.
	return a.ensureH264StreamPlayer(id, path, r, size, false, fallback)
}
