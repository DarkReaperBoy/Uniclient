package gui

import (
	"time"

	"uniclient/engine"
)

func viewerMayStream(it engine.SharedMediaItem) bool {
	if it.LocalPath != "" || !viewerIsVideo(it) {
		return false
	}
	if inAppVideoExt(it.FileName) {
		return true
	}
	return it.MimeType == "video/mp4"
}

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

func (a *App) startStreamedVideoNote(m *engine.CachedMessage) bool {
	if a.eng == nil || m == nil || m.MsgID == "" {
		return false
	}
	if st, ok := h264Players.peek(m.MsgID); ok && !st.failed && st.path != "" && (st.parsed || st.reading) {
		return true
	}
	r, size, path, err := a.eng.OpenMediaStream(m.AccountID, m.ChatID, m.MsgID, 0)
	if err != nil {
		return false
	}
	fallback := func() {
		a.setPlayOnDone(m.AccountID, m.ChatID, m.MsgID, 0)
		go func() {
			if err := a.eng.RequestDownload(m.AccountID, m.ChatID, m.MsgID, 0, 0); err != nil {
				a.setToast("Download failed: " + err.Error())
			}
		}()
	}
	return a.ensureH264StreamPlayer(m.MsgID, path, r, size, true, fallback)
}

func (a *App) startStreamedViewerVideo(v *viewerState, it engine.SharedMediaItem) bool {
	if v == nil || a.eng == nil || !viewerMayStream(it) {
		return false
	}
	acct, chat, id := v.accountID, v.chatID, it.MsgID
	if st, ok := h264Players.peek(id); ok && !st.failed && st.path != "" && (st.parsed || st.reading) {
		return true
	}
	r, size, path, err := a.eng.OpenMediaStream(acct, chat, id, 0)
	if err != nil {
		return false
	}
	fallback := func() {
		a.setOpenOnDone(acct, chat, id, 0)
		go func() {
			if err := a.eng.RequestDownload(acct, chat, id, 0, 0); err != nil {
				a.setToast("Download failed: " + err.Error())
			}
		}()
		a.setToast("Downloading video…")
	}
	return a.ensureH264StreamPlayer(id, path, r, size, false, fallback)
}
