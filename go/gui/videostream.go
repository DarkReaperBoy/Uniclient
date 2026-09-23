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

// streamShouldJoinAudio decides on DownloadComplete whether THIS active
// inline player wants its sound started at its own playhead. Guards:
// there is a player, it is parsed and currently playing (a paused or
// stopped picture must not have sound start behind it), and it is
// streaming THIS exact path (the download-driven playOnDone flow, which
// owns its own audio start, is ordered before this call and must not be
// double-started). Pure — unit-tested.
func streamShouldJoinAudio(st h264PlayerState, have bool, localPath string) bool {
	return have && st.parsed && st.playing && st.path == localPath && st.video != nil
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
	r, size, path, err := a.eng.OpenMediaStream(m.AccountID, m.ChatID, m.MsgID, 0)
	if err != nil {
		return false // no ranged read (or no row): old flow
	}
	fallback := func() {
		// Parse rejected the bytes (e.g. HEVC-in-MP4): close our stream
		// (the full download takes the file over) and do exactly what
		// the tap would have done with no stream available.
		r.Close()
		a.setPlayOnDone(m.AccountID, m.ChatID, m.MsgID, 0)
		go func() {
			if err := a.eng.RequestDownload(m.AccountID, m.ChatID, m.MsgID, 0, 0); err != nil {
				a.setToast("Download failed: " + err.Error())
			}
		}()
	}
	if a.ensureH264StreamPlayer(m.MsgID, path, r, size, true, fallback) {
		return true
	}
	r.Close()
	return false
}

// startStreamedViewerVideo is the viewer's row-281 fast path (loop=false:
// the viewer plays through, transport controls included — they act on
// the same player cache entry a downloaded clip would publish).
func (a *App) startStreamedViewerVideo(v *viewerState, it engine.SharedMediaItem) bool {
	if v == nil || a.eng == nil || !viewerMayStream(it) {
		return false
	}
	acct, chat, id := v.accountID, v.chatID, it.MsgID
	r, size, path, err := a.eng.OpenMediaStream(acct, chat, id, 0)
	if err != nil {
		return false
	}
	fallback := func() {
		r.Close()
		a.setOpenOnDone(acct, chat, id, 0)
		go func() {
			if err := a.eng.RequestDownload(acct, chat, id, 0, 0); err != nil {
				a.setToast("Download failed: " + err.Error())
			}
		}()
		a.setToast("Downloading video…")
	}
	if a.ensureH264StreamPlayer(id, path, r, size, false, fallback) {
		return true
	}
	r.Close()
	return false
}
