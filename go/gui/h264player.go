package gui

// h264player.go — slice 220: round video notes play INSIDE the chat
// bubble, circle-cropped and looping, which is what AyuGram/tdesktop do
// with video messages (they are players, not links to a viewer).
//
// The decode pipeline is slice 219's pure-Go `uniclient/h264vid`
// (bit-exact against ffmpeg — see research/h264_decoder.md). Everything
// here mirrors vp9player.go on purpose: one async parse per message, a
// background producer decoding ahead of the display clock, tap-to-toggle,
// power saving holds a static frame, and an undecodable file falls
// through to the honest viewer/system path instead of a dead bubble
// (§1.10).
//
// Audio is started by slice 225 whenever publish() starts the picture:
// the engine decodes the MP4's AAC track (slice 223/224) and holds the
// volume gain, so this file only has to keep the two halves in step —
// play, pause and loop-wrap are mirrored into the engine by videoaudio.go.
// A clip with no audio track plays picture-only and quietly, which is
// correct rather than a failure.

import (
	"errors"
	"image"
	"io"
	"os"
	"sync"
	"time"

	"gioui.org/layout"
	"gioui.org/op"

	"uniclient/engine"
	"uniclient/h264vid"
)

// ── tap state machine (pure) ────────────────────────────────────────────

// noteAction is what a tap on a round video note should do.
type noteAction int

const (
	// noteActionViewer: the file cannot be decoded in pure Go — hand it
	// to the fullscreen viewer rather than leaving a dead bubble.
	noteActionViewer noteAction = iota
	// noteActionDownload: the bytes are not on disk yet.
	noteActionDownload
	// noteActionWait: a parse is in flight (or about to be started).
	noteActionWait
	// noteActionPlay: (re)start the inline loop.
	noteActionPlay
	// noteActionPause: freeze the inline loop where it is.
	noteActionPause
)

func (a noteAction) String() string {
	switch a {
	case noteActionViewer:
		return "viewer"
	case noteActionDownload:
		return "download"
	case noteActionWait:
		return "wait"
	case noteActionPlay:
		return "play"
	case noteActionPause:
		return "pause"
	}
	return "unknown"
}

// noteTapAction maps a tap to its outcome. `downloaded` is the message's
// file state, `p` a cache SNAPSHOT (nil when nothing has been parsed yet).
// It takes a snapshot rather than a live entry on purpose: the parse
// goroutine writes those flags, so no caller may touch them off-lock.
// Pure — unit-tested.
func noteTapAction(p *h264PlayerState, downloaded bool) noteAction {
	if !downloaded {
		return noteActionDownload
	}
	if p == nil {
		return noteActionWait // caller ensures the parse starts
	}
	if p.failed {
		return noteActionViewer
	}
	if p.reading || !p.parsed {
		return noteActionWait
	}
	if p.playing {
		return noteActionPause
	}
	return noteActionPlay
}

// ── per-message player cache ────────────────────────────────────────────

// h264Player is one message's parsed clip + playhead. Its fields are
// ONLY touched under the cache mutex — the render path and the parse
// goroutine both reach them, so readers take a h264PlayerState snapshot
// instead of holding this pointer (a -race run caught exactly that).
type h264Player struct {
	video  *h264vid.Video
	player *h264vid.Player
	path   string // source file (a changed path re-parses)

	// Playhead. `start` is chosen so that time.Since(start) equals the
	// paused position on resume, which keeps FrameAt's elapsed monotonic
	// across pause/resume (a backward jump would rewind the producer).
	start  time.Time
	paused time.Duration

	playing bool
	parsed  bool
	failed  bool      // permanently unplayable (bad container / undecodable)
	reading bool      // async file read + parse in flight
	loop    bool      // round note (wrap) vs viewer (play through)
	src     io.Closer // open stream reader this entry owns (nil for files; slice 230)
}

// h264PlayerState is an immutable snapshot of an entry, copied under the
// cache lock. Everything a render or tap decision needs rides along.
type h264PlayerState struct {
	video   *h264vid.Video
	player  *h264vid.Player
	path    string
	parsed  bool
	failed  bool
	reading bool
	playing bool
	loop    bool
}

func snapshot(p *h264Player) h264PlayerState {
	if p == nil {
		return h264PlayerState{}
	}
	return h264PlayerState{
		video: p.video, player: p.player, path: p.path,
		parsed: p.parsed, failed: p.failed, reading: p.reading, playing: p.playing,
		loop: p.loop,
	}
}

// h264PlayerCache keeps per-msgID players; pruned wholesale when
// oversized (same policy as tgsPlayers/webmPlayers). Players own decode
// goroutines, so eviction stops them asynchronously — a mid-decode Stop
// could otherwise stall the frame thread.
type h264PlayerCache struct {
	mu      sync.Mutex
	players map[string]*h264Player
}

var h264Players = &h264PlayerCache{players: make(map[string]*h264Player)}

// h264PlayerMax bounds resident clips. Round notes are square and short,
// but a decoded frame is w*h*4 bytes, so this stays conservative.
const h264PlayerMax = 48

// closeSrc closes an entry's stream reader, if any, and forgets it (so
// a second close cannot double-fire the engine's file guard — mediaStream
// is idempotent anyway, but the ownership rule is "closed exactly once
// here"). Caller holds c.mu.
func closeSrc(p *h264Player) {
	if p != nil && p.src != nil {
		src := p.src
		p.src = nil
		src.Close()
	}
}

// evictLocked stops every producer, closes every source and drops the
// whole map. Caller holds c.mu.
func (c *h264PlayerCache) evictLocked() {
	for _, old := range c.players {
		stopH264Player(old)
		closeSrc(old)
	}
	c.players = make(map[string]*h264Player)
}

// get returns a snapshot of the entry for msgID, creating it if needed.
// Entries are never handed out directly: only the cache touches fields.
func (c *h264PlayerCache) get(msgID string) (h264PlayerState, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p, ok := c.players[msgID]; ok {
		return snapshot(p), true
	}
	if len(c.players) >= h264PlayerMax {
		c.evictLocked()
	}
	p := &h264Player{}
	c.players[msgID] = p
	return snapshot(p), true
}

// peek returns a snapshot without creating an entry (render-path lookup
// — a bubble that is not playing must not grow the cache).
func (c *h264PlayerCache) peek(msgID string) (h264PlayerState, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	p, ok := c.players[msgID]
	if !ok {
		return h264PlayerState{}, false
	}
	return snapshot(p), true
}

// len reports how many entries are resident (test hook for eviction).
func (c *h264PlayerCache) len() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return len(c.players)
}

// publish installs a parsed clip and starts its producer. loop selects
// round-note behaviour (wrap at the end) versus an ordinary video (play
// through and rest on the final frame) — a viewer must not spin a
// regular clip forever.
func (c *h264PlayerCache) publish(msgID, path string, video *h264vid.Video, loop bool) *h264vid.Player {
	return c.publishWithSrc(msgID, path, video, loop, nil)
}

// publishWithSrc installs a parsed clip — loop selects round-note
// behaviour (wrap at the end) versus an ordinary video (play through and
// rest on the final frame) — and, for streamed sources, the open reader
// the decode keeps pulling chunks through. Replacing an entry closes the
// old reader: after the swap the old picture has no consumer, and a
// dropped fd would leak for the whole session (slice 230). Overflow
// evicts wholesale HERE too — the old check lived in get(), which
// nothing calls on this cache.
func (c *h264PlayerCache) publishWithSrc(msgID, path string, video *h264vid.Video, loop bool, src io.Closer) *h264vid.Player {
	if video == nil {
		return nil
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	p := c.players[msgID]
	if p == nil {
		if len(c.players) >= h264PlayerMax {
			c.evictLocked()
		}
		p = &h264Player{}
		c.players[msgID] = p
	}
	if p.player != nil {
		stopH264Player(p) // source changed: never leak the old producer
	}
	closeSrc(p) // old source gone: its reader has no consumer anymore
	p.video, p.path = video, path
	p.parsed, p.failed, p.reading = true, false, false
	p.loop = loop
	p.src = src
	p.paused = 0
	p.start = time.Now()
	p.playing = true
	pl := video.NewPlayer()
	pl.SetLoop(loop)
	pl.Start()
	p.player = pl
	return pl
}

// pause freezes the playhead where it is.
func (c *h264PlayerCache) pause(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p := c.players[msgID]; p != nil && p.playing {
		p.paused = time.Since(p.start)
		p.playing = false
	}
}

// resume continues from the frozen position.
func (c *h264PlayerCache) resume(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	p := c.players[msgID]
	if p == nil || !p.parsed || p.playing {
		return
	}
	// A finished non-looping clip restarts from the top: pressing play on
	// an ended video has to DO something rather than sit on the last frame.
	if p.video != nil && p.video.Total > 0 && p.paused >= p.video.Total {
		p.paused = 0
	}
	p.start = time.Now().Add(-p.paused)
	p.playing = true
}

// elapsed reports the playhead (frozen while paused). Pure w.r.t. the
// paused state — unit-tested.
func (c *h264PlayerCache) elapsed(msgID string) time.Duration {
	c.mu.Lock()
	defer c.mu.Unlock()
	p := c.players[msgID]
	if p == nil {
		return 0
	}
	if p.playing {
		return time.Since(p.start)
	}
	return p.paused
}

// failParse pins the message to the honest fallback (no re-parse churn).
// It creates the entry when needed so a failure is never lost — losing it
// would let a known-bad file churn a fresh parse on every single tap.
func (c *h264PlayerCache) failParse(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	p := c.players[msgID]
	if p == nil {
		if len(c.players) >= h264PlayerMax {
			c.evictLocked()
		}
		p = &h264Player{}
		c.players[msgID] = p
	}
	p.failed, p.reading, p.playing = true, false, false
}

// reset drops a parsed clip (new source file for the message).
func (c *h264PlayerCache) reset(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p := c.players[msgID]; p != nil {
		stopH264Player(p)
		closeSrc(p) // the stream reader must not outlive its entry (slice 230)
		p.video, p.player, p.path = nil, nil, ""
		p.parsed, p.failed, p.reading, p.playing = false, false, false, false
		p.loop = false
		p.paused = 0
	}
}

// markReading claims the async read slot; false while one is in flight.
func (c *h264PlayerCache) markReading(msgID string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	p := c.players[msgID]
	if p == nil {
		if len(c.players) >= h264PlayerMax {
			c.evictLocked() // insert paths must bound the cache too (slice 230)
		}
		p = &h264Player{}
		c.players[msgID] = p
	}
	if p.reading {
		return false
	}
	p.reading = true
	return true
}

// endReading releases the read slot (retryable failures).
func (c *h264PlayerCache) endReading(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p := c.players[msgID]; p != nil {
		p.reading = false
	}
}

// stopH264Player stops a producer asynchronously. Caller holds c.mu, so
// it must never wait on the goroutine (a mid-decode Stop can block).
func stopH264Player(p *h264Player) {
	if p != nil && p.player != nil {
		pl := p.player
		p.player = nil
		go pl.Stop()
	}
}

// ── parse (async, once per message) ────────────────────────────────────

// ensureH264Player kicks off the one-time async read+parse of a clip; a
// successful publish starts playback immediately, which is what makes
// "tap a video note" and "play the video note" the same gesture. loop
// selects round-note looping versus play-through, and onFail (optional)
// runs when the file cannot be read or decoded so a caller can fall back
// honestly instead of leaving a dead bubble or a dead play button.
// acct/chat/msgID identify the clip for the engine's audio half — audio
// starts only once publish() has really started the picture, so the two
// clocks begin together instead of the sound leading the video.
func (a *App) ensureH264Player(acct, chat, msgID, path string, loop bool, onFail ...func()) {
	if msgID == "" || path == "" {
		return
	}
	notify := func() {
		for _, fn := range onFail {
			if fn != nil {
				fn()
			}
		}
	}
	p, _ := h264Players.peek(msgID)
	if p.path == path && (p.parsed || p.failed || p.reading) {
		return // already parsed, already failing, or in flight
	}
	if p.path != "" && p.path != path {
		h264Players.reset(msgID) // source swapped: re-parse
	}
	if !h264Players.markReading(msgID) {
		return
	}
	go func() {
		data, err := os.ReadFile(path)
		if err != nil {
			h264Players.endReading(msgID) // retry on a later tap
			notify()                      // viewer: fall back, don't hang
			return
		}
		video, err := h264vid.Parse(data)
		if err != nil || video == nil {
			h264Players.failParse(msgID)
			a.invalidate()
			notify()
			return
		}
		pl := h264Players.publish(msgID, path, video, loop)
		if pl == nil {
			h264Players.failParse(msgID)
			a.invalidate()
			notify()
			return
		}
		// The picture's clock just started (publish sets start=now), so
		// this is the one right moment to start the matching audio.
		a.videoAudioPlay(acct, chat, msgID, path)
		a.invalidate()
		// Repaint once the first frame is decoded so the bubble swaps
		// from its thumbnail to the live video.
		a.repaintOnFirstFrame(pl)
	}()
}

// repaintOnFirstFrame invalidates as soon as the clip's first frame is
// decoded (or the decode fails), so the surface swaps from its poster to
// the live video instead of waiting for the next unrelated redraw.
// Shared by the downloaded-file and streamed entry points.
func (a *App) repaintOnFirstFrame(pl *h264vid.Player) {
	go func() {
		for i := 0; i < 400; i++ { // ≤ 2s at 5ms
			if pl.DecodedCount() >= 1 || pl.Failed() != nil {
				a.invalidate()
				return
			}
			time.Sleep(5 * time.Millisecond)
		}
	}()
}

// publishStreamedClip parses a NOT-yet-downloaded clip straight from the
// engine's fetch-on-read stream and publishes it into the cache — the
// row-281 fast path (slice 229). App-free on purpose: failures return an
// error so the caller runs the honest fallback, and it stays
// unit-testable with plain fixture bytes.
func publishStreamedClip(msgID, path string, ra io.ReaderAt, size int64, loop bool) (*h264vid.Player, error) {
	if msgID == "" || path == "" || ra == nil || size <= 0 {
		return nil, errors.New("gui: streamed clip has no usable source")
	}
	sec := io.NewSectionReader(ra, 0, size)
	video, err := h264vid.ParseSeek(sec)
	if err != nil {
		return nil, err
	}
	var closer io.Closer
	if c, ok := ra.(io.Closer); ok {
		closer = c // the cache owns it from here (close on reset/replace/evict)
	}
	pl := h264Players.publishWithSrc(msgID, path, video, loop, closer)
	if pl == nil {
		return nil, errors.New("gui: streamed clip published no player")
	}
	return pl, nil
}

// ensureH264StreamPlayer kicks off streamed playback (row 281): parse off
// the UI thread, publish, repaint on the first frame. OWNERSHIP RULE
// (slice 230): it CONSUMES ra on every path — decline paths close it
// themselves, and the parse goroutine either hands it to the cache (which
// closes it on reset/replace/evict) or closes it BEFORE running onFail.
// Callers must never close it. Returns false ONLY when it did not take
// the job (invalid args, or a file already known permanently unplayable)
// — the caller then runs download-then-play exactly as before (§1.10:
// never a dead bubble). onFail (optional) runs when the parse rejects the
// bytes, so an HEVC-in-MP4 still reaches the viewer/system path. NO audio
// starts here — the file is incomplete; sound joins when the bytes land
// (state.go → streamJoinAt → videoAudioPlayAt at the playhead).
func (a *App) ensureH264StreamPlayer(msgID, path string, ra io.ReaderAt, size int64, loop bool, onFail ...func()) bool {
	closeRa := func() {
		if c, ok := ra.(io.Closer); ok {
			c.Close()
		}
	}
	if msgID == "" || path == "" || ra == nil || size <= 0 {
		closeRa()
		return false
	}
	p, _ := h264Players.peek(msgID)
	if p.path != "" && p.path != path {
		h264Players.reset(msgID) // source swapped: stale verdicts AND the old reader go
		p = h264PlayerState{}
	}
	if p.failed {
		closeRa()
		return false // permanent verdict: decline so the caller's fallback runs
	}
	if p.path == path && (p.parsed || p.reading) {
		closeRa()
		return true // already serving this exact file
	}
	if !h264Players.markReading(msgID) {
		closeRa()
		return true // another goroutine owns the parse
	}
	go func() {
		pl, err := publishStreamedClip(msgID, path, ra, size, loop)
		if err != nil {
			h264Players.endReading(msgID)
			if h264vid.IsPermanent(err) {
				h264Players.failParse(msgID) // verdict about these bytes
			}
			// Retryable failures leave a clean entry (next tap re-parses).
			closeRa() // close BEFORE the fallback hands the file to the downloader
			for _, fn := range onFail {
				if fn != nil {
					fn()
				}
			}
			a.invalidate()
			return
		}
		a.repaintOnFirstFrame(pl)
		a.invalidate()
	}()
	return true
}

// startVideoNoteInline is the download-completion entry point: the bytes
// just landed, so parse them and play them in the bubble at once. The
// account and chat ride along so the matching audio can be attributed to
// this message in the engine's playback snapshot.
func (a *App) startVideoNoteInline(acct, chat, msgID, path string) {
	a.ensureH264Player(acct, chat, msgID, path, true)
}

// tapVideoNote handles a tap on an already-downloaded round note by
// toggling the inline loop. false means "not handled" — the caller falls
// through to the fullscreen viewer, so a file our decoder rejects still
// opens (§1.10: never a dead bubble).
func (a *App) tapVideoNote(m *engine.CachedMessage) bool {
	if m == nil || m.MediaLocalPath == "" {
		return false
	}
	// No entry at all → nil snapshot → noteActionWait, which starts the
	// parse. A snapshot is taken, never a live entry: publish() writes
	// these flags from the parse goroutine.
	st, have := h264Players.peek(m.MsgID)
	var p *h264PlayerState
	if have {
		p = &st
	}
	switch noteTapAction(p, true) {
	case noteActionWait:
		a.ensureH264Player(m.AccountID, m.ChatID, m.MsgID, m.MediaLocalPath, true)
		return true
	case noteActionPlay:
		h264Players.resume(m.MsgID)
		a.videoAudioPlay(m.AccountID, m.ChatID, m.MsgID, m.MediaLocalPath)
		a.invalidate()
		return true
	case noteActionPause:
		h264Players.pause(m.MsgID)
		a.videoAudioPause(m.MsgID)
		a.invalidate()
		return true
	default: // noteActionViewer / noteActionDownload → caller's fallback
		return false
	}
}

// ── inline "play when the download lands" marker ───────────────────────

// setPlayOnDone marks a media download so completion plays it IN-CHAT
// instead of handing it to the system player (slice 86's handoff stays
// reserved for every other type).
func (a *App) setPlayOnDone(acct, chat, msg string, seq int) {
	a.mu.Lock()
	if a.playOnDone == nil {
		a.playOnDone = make(map[string]bool)
	}
	a.playOnDone[dlKey(acct, chat, msg, seq)] = true
	a.mu.Unlock()
}

// consumePlayOnDone reports and clears the inline-play mark.
func (a *App) consumePlayOnDone(acct, chat, msg string, seq int) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.consumePlayOnDoneLocked(acct, chat, msg, seq)
}

// consumePlayOnDoneLocked is consumePlayOnDone for callers holding a.mu.
func (a *App) consumePlayOnDoneLocked(acct, chat, msg string, seq int) bool {
	if a.playOnDone == nil {
		return false
	}
	k := dlKey(acct, chat, msg, seq)
	v := a.playOnDone[k]
	delete(a.playOnDone, k)
	return v
}

// ── rendering ───────────────────────────────────────────────────────────

// drawVideoNoteFrame renders the playing round note's current frame,
// circle-cropped, inside a diameter×diameter box; false when there is
// nothing to draw yet (the caller keeps the thumbnail+badge).
func (a *App) drawVideoNoteFrame(gtx layout.Context, msgID string, diameter int) (layout.Dimensions, bool) {
	e, ok := h264Players.peek(msgID)
	if !ok || !e.playing || e.video == nil || e.player == nil || diameter <= 0 {
		return layout.Dimensions{}, false
	}
	// The producer died mid-play (a fetch failed): drop the entry so the
	// next tap re-opens the source, instead of freezing on one frame while
	// the engine keeps playing orphan sound (slice 230, §1.10).
	if e.player.Failed() != nil {
		h264Players.reset(msgID)
		a.videoAudioPause(msgID)
		return layout.Dimensions{}, false
	}
	elapsed := h264Players.elapsed(msgID)

	// Power saving: hold the current frame with no re-arm — the loop is
	// the battery cost (same contract as stickers/emoji).
	if powerSavingBlocks(powerSaving.flags, powerSaving.forceAll, psClassVideo) {
		if img := e.player.FrameAt(elapsed); img != nil {
			return drawImageEllipse(gtx, img, diameter), true
		}
		return layout.Dimensions{Size: image.Pt(diameter, diameter)}, true
	}

	img := e.player.FrameAt(elapsed)
	if img == nil {
		// Producer warming up: keep the thumbnail for this paint.
		return layout.Dimensions{}, false
	}
	// The picture is looping; make sure the sound is still keeping up.
	// After the first pass the engine has played its track through, so
	// without this the note would loop silently from then on.
	a.videoAudioLoop(msgID)
	dims := drawImageEllipse(gtx, img, diameter)
	gtx.Execute(op.InvalidateCmd{At: time.Now().Add(e.player.NextFrameIn(elapsed))})
	return dims, true
}
