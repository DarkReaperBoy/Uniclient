package gui

// videoaudio.go — slice 225: SOUND for in-app video and the volume
// slider, the last piece of parity row 276 ("Playback controls (video):
// play/pause/seek/volume/fullscreen").
//
// The chain built so far: slice 219 decoded H.264 in pure Go, slice 220
// played round notes in the bubble, slice 221 added play/pause/scrub and
// clocks in the viewer, slice 223 read the AAC track out of an MP4
// byte-identically to ffmpeg, slice 224 made the engine decode it to
// mono 48 kHz and apply a gain. This file joins the two halves: whenever
// the picture plays, the engine plays the matching audio; whenever it
// pauses, seeks or loops, the audio does the same.
//
// Design notes worth keeping:
//
//   - ONE media player exists in the engine, so starting video audio
//     switches whatever was playing (music, a voice note). That is the
//     intended single-media behaviour, not a bug: pause/resume/seek below
//     only ever act when the engine is on OUR message, so touching a video
//     never pauses someone else's track.
//
//   - The picture and the sound are two real-time clocks started
//     together: the GUI's playhead is time.Since(start) and the audio
//     advances only as the device pulls samples. Neither accumulates
//     drift against the other — their fixed offset is the device's
//     output buffer latency. Round notes LOOP while the engine plays
//     through, so the audio is re-armed at each wrap (videoAudioLoop).
//
//   - An MP4 with no audio track, HE-AAC, or a platform without a device
//     all mean "picture only". The first is correct behaviour and stays
//     quiet; the others toast, because a video that silently loses its
//     sound looks broken and §1.10 forbids hiding a real failure.

import (
	"errors"
	"log"
	"time"

	"uniclient/aacaud"
	"uniclient/audio"
	"uniclient/engine"
)

// videoAudioAvailable reports whether this platform has a speaker
// backend at all. The volume control is drawn only then — a slider that
// moves nothing is exactly the UI section 1.10 forbids.
func videoAudioAvailable() bool { return audio.Available() }

// viewerIdent returns the identity the viewer was opened with, which the
// engine stores on its playback snapshot (voice notes compare the same
// three fields to decide whether a tap toggles or switches).
func (a *App) viewerIdent() (acct, chat string) {
	if v := a.viewer; v != nil {
		return v.accountID, v.chatID
	}
	return "", ""
}

// viewerVideoAudioPlay starts or resumes audio for a viewer item, using
// the viewer's identity and the item's path.
func (a *App) viewerVideoAudioPlay(it engine.SharedMediaItem) {
	acct, chat := a.viewerIdent()
	a.videoAudioPlay(acct, chat, it.MsgID, it.LocalPath)
}

// videoAudioMine reports whether the engine's single media player is
// currently holding THIS message's audio, and therefore whether a
// pause/resume/seek from the video controls should touch it at all.
// An empty msgID is never "mine" — it would make every video claim every
// track.
func videoAudioMine(st engine.PlaybackState, msgID string) bool {
	if msgID == "" {
		return false
	}
	return st.MsgID == msgID
}

// isSilentVideoErr reports whether a PlayMedia failure simply means "this
// clip has no sound". That is a normal outcome for a video message with
// no audio track, so it must not toast on every play.
func isSilentVideoErr(err error) bool {
	return errors.Is(err, aacaud.ErrNoAudio)
}

// videoAudioShouldLoop decides whether the engine's audio must be
// re-armed. Round notes loop forever while the engine plays a track
// through exactly once, so without this the picture would loop silently
// after the first pass.
//
// Every guard exists for a real case: not our track (music is playing),
// a picture that has itself stopped (a video that played through must
// NOT resurrect its audio), no device (nothing to re-arm), audio still
// running or paused, and a duration-less state. The 50 ms slack keeps the
// restart from firing while the last samples are still draining.
// Pure — unit-tested.
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

// startVideoAudio plays the clip's AAC track through the engine player.
// It runs off the UI thread (the decode reads the file) and reports how
// it went so callers that already own a toast path can stay quiet.
func (a *App) startVideoAudio(acct, chat, msgID, path string) {
	if a.eng == nil || path == "" || msgID == "" {
		return
	}
	a.runVideoAudio(func() error { return a.eng.PlayMedia(acct, chat, msgID, path) })
}

// videoAudioPlayAt starts the sound at startAt — slice 229's join point
// (row 281): a clip that played from the fetch-on-read stream only has
// its bytes when the file completes, so the sound must start WHERE THE
// PICTURE IS rather than at zero. Same honesty rules as
// startVideoAudio: a silent track stays quiet, every other failure is
// said once.
func (a *App) videoAudioPlayAt(acct, chat, msgID, path string, startAt time.Duration) {
	if a.eng == nil || path == "" || msgID == "" {
		return
	}
	a.runVideoAudio(func() error { return a.eng.PlayMediaAt(acct, chat, msgID, path, startAt) })
}

// runVideoAudio plays off the UI thread and reports the outcome once —
// shared by the at-onset and caught-up entry points so their error
// behaviour cannot drift.
func (a *App) runVideoAudio(play func() error) {
	if a.eng == nil {
		return
	}
	go func() {
		if err := play(); err != nil {
			if isSilentVideoErr(err) {
				return // no audio track: picture-only is correct, not a failure
			}
			// HE-AAC (out of scope for the pure-Go decoder), a container
			// without AAC, or no audio device: the picture still plays,
			// so say it once rather than leaving a mysteriously silent
			// video — and the system-player handoff remains one tap away.
			log.Printf("gui: video audio: %v", err)
			a.setToast("Playing video without sound: " + err.Error())
		} else {
			a.startPlaybackTickerIfNeeded()
		}
	}()
}

// videoAudioPlay is the play path: resume OUR paused track when the
// engine already holds it (pause → play must not restart from zero),
// otherwise hand the new clip to the engine, which switches playback.
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
	// Not our track: hand the new clip to PlayMedia, which SWITCHES
	// playback (one media at a time, the engine's contract). Playing a
	// video therefore stops the music that was going — correct, and
	// strictly better than a precedence bug that once made "something
	// else is playing" skip video audio entirely.
	a.startVideoAudio(acct, chat, msgID, path)
}

// videoAudioPause freezes our track with the picture. It deliberately
// does nothing when the engine is on another message, so pausing a video
// cannot pause someone's music.
func (a *App) videoAudioPause(msgID string) {
	if a.eng == nil {
		return
	}
	st := a.eng.MediaState()
	if videoAudioMine(st, msgID) && st.Playing {
		a.eng.TogglePauseMedia()
	}
}

// videoAudioSeek moves our track to the same fraction the scrubber put
// the picture at — one drag, two clocks, same target.
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

// videoAudioLoop re-arms the audio when a looping picture has outrun it.
// Called from the frame draw path, which only runs while the clip is
// actually painting — so a stopped video never restarts its sound.
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
		log.Printf("gui: video audio loop: %v", err)
	}
}

// setMediaVolume applies the slider's value: the live half (audible
// immediately) and the persistent half (survives a restart, which is what
// makes it a setting rather than a decoration).
func (a *App) setMediaVolume(v float64) {
	if a.eng == nil {
		return
	}
	a.eng.SetMediaVolume(v) // clamps
	vv := v
	go func() {
		if err := a.eng.UpdateConfigFromBridge(&engine.ConfigChanges{MediaVolume: &vv}); err != nil {
			log.Printf("gui: volume persist: %v", err)
		}
	}()
}

// mediaVolume reads the gain for the slider track. It is simply the
// player's live value: the engine seeds it from config when the player is
// first created, so a restart opens at the saved setting, and a drag
// lands here within the same frame (the persist path is async and must
// never be what the handle paints from).
func (a *App) mediaVolume() float64 {
	if a.eng == nil {
		return 1
	}
	return a.eng.MediaState().Volume // 0 is a real mute and round-trips
}
