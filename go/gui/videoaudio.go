package gui

import (
	"errors"
	"log"
	"time"

	"uniclient/aacaud"
	"uniclient/audio"
	"uniclient/engine"
)

func videoAudioAvailable() bool { return audio.Available() }

func (a *App) viewerIdent() (acct, chat string) {
	if v := a.viewer; v != nil {
		return v.accountID, v.chatID
	}
	return "", ""
}

func (a *App) viewerVideoAudioPlay(it engine.SharedMediaItem) {
	acct, chat := a.viewerIdent()
	a.videoAudioPlay(acct, chat, it.MsgID, it.LocalPath)
}

func videoAudioMine(st engine.PlaybackState, msgID string) bool {
	if msgID == "" {
		return false
	}
	return st.MsgID == msgID
}

func isSilentVideoErr(err error) bool {
	return errors.Is(err, aacaud.ErrNoAudio)
}

func videoAudioShouldLoop(mine, videoPlaying, hasAudio, audioPlaying, audioPaused bool, pos, dur float64) bool {
	if !mine || !videoPlaying || !hasAudio {
		return false
	}
	if audioPlaying || audioPaused {
		return false
	}
	if dur <= 0 {
		return false
	}
	return pos >= dur-0.05
}

func (a *App) startVideoAudio(acct, chat, msgID, path string) {
	if a.eng == nil || path == "" || msgID == "" {
		return
	}
	a.runVideoAudio(func() error { return a.eng.PlayMedia(acct, chat, msgID, path) })
}

func (a *App) videoAudioPlayAt(acct, chat, msgID, path string, startAt time.Duration) {
	if a.eng == nil || path == "" || msgID == "" {
		return
	}
	a.runVideoAudio(func() error { return a.eng.PlayMediaAt(acct, chat, msgID, path, startAt) })
}

func (a *App) runVideoAudio(play func() error) {
	if a.eng == nil {
		return
	}
	go func() {
		if err := play(); err != nil {
			if isSilentVideoErr(err) {
				return
			}
			log.Printf("gui: video audio: %v", err)
			a.setToast("Playing video without sound: " + err.Error())
		} else {
			a.startPlaybackTickerIfNeeded()
		}
	}()
}

func (a *App) videoAudioPlay(acct, chat, msgID, path string) {
	if a.eng == nil {
		return
	}
	st := a.eng.MediaState()
	if videoAudioMine(st, msgID) {
		if st.Paused {
			a.eng.TogglePauseMedia()
			a.startPlaybackTickerIfNeeded()
		}
		return
	}
	a.startVideoAudio(acct, chat, msgID, path)
}

func (a *App) videoAudioPause(msgID string) {
	if a.eng == nil {
		return
	}
	st := a.eng.MediaState()
	if videoAudioMine(st, msgID) && st.Playing {
		a.eng.TogglePauseMedia()
	}
}

func (a *App) videoAudioSeek(msgID string, frac float64) {
	if a.eng == nil {
		return
	}
	if !videoAudioMine(a.eng.MediaState(), msgID) {
		return
	}
	if err := a.eng.SeekMedia(frac); err != nil {
		log.Printf("gui: video audio seek: %v", err)
	}
}

func loopLogAllowed(last *time.Time, now time.Time, minGap time.Duration) bool {
	if !last.IsZero() && now.Sub(*last) < minGap {
		return false
	}
	*last = now
	return true
}

func (a *App) videoAudioLoop(msgID string) {
	if a.eng == nil {
		return
	}
	st := a.eng.MediaState()
	videoPlaying := false
	if p, ok := h264Players.peek(msgID); ok {
		videoPlaying = p.playing
	}
	if !videoAudioShouldLoop(videoAudioMine(st, msgID), videoPlaying,
		st.HasAudio, st.Playing, st.Paused, st.Position, st.Duration) {
		return
	}
	if err := a.eng.SeekMedia(0); err != nil {
		a.loopLogMu.Lock()
		allowed := loopLogAllowed(&a.loopLogLast, time.Now(), 10*time.Second)
		a.loopLogMu.Unlock()
		if allowed {
			log.Printf("gui: video audio loop: %v", err)
		}
	}
}

func (a *App) setMediaVolume(v float64) {
	if a.eng == nil {
		return
	}
	a.eng.SetMediaVolume(v)
	vv := v
	go func() {
		if err := a.eng.UpdateConfigFromBridge(&engine.ConfigChanges{MediaVolume: &vv}); err != nil {
			log.Printf("gui: volume persist: %v", err)
		}
	}()
}

func (a *App) mediaVolume() float64 {
	if a.eng == nil {
		return 1
	}
	return a.eng.MediaState().Volume
}
