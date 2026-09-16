package gui

// vp9player.go — slice 216: WebM/VP9 video sticker + video emoji playback
// in the chat, through the pure-Go vp9anim pipeline (uniclient/webm demux
// + govpx VP9 decode, both verified against official test vectors). The
// per-message player cache mirrors tgsPlayers: one async parse per
// message, a background producer decoding ahead of the display clock,
// tap-to-replay, power-saving renders the first frame statically, and a
// failed parse pins the honest static-thumbnail fallback (§1.10).

import (
	"image"
	"os"
	"sync"
	"time"

	"gioui.org/layout"
	"gioui.org/op"

	"uniclient/engine"
	"uniclient/vp9anim"
)

// ── per-message player cache ──────────────────────────────────────────────

// webmPlayer is one message's parsed animation + play clock.
type webmPlayer struct {
	anim    *vp9anim.Animation
	player  *vp9anim.Player
	start   time.Time
	path    string // source file (a changed path re-parses)
	parsed  bool
	failed  bool // permanently unplayable (bad container/stream)
	reading bool // async file read + parse in flight
}

// webmPlayerCache keeps per-msgID players; pruned wholesale when
// oversized (same policy as tgsPlayers). Video players own goroutines,
// so eviction stops them (async — a mid-decode Stop could stall a frame).
type webmPlayerCache struct {
	mu      sync.Mutex
	players map[string]*webmPlayer
}

var webmPlayers = &webmPlayerCache{players: make(map[string]*webmPlayer)}

const webmPlayerMax = 96

func (c *webmPlayerCache) get(msgID string) *webmPlayer {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p, ok := c.players[msgID]; ok {
		return p
	}
	if len(c.players) >= webmPlayerMax {
		for _, p := range c.players {
			if p.player != nil {
				go p.player.Stop()
			}
		}
		c.players = make(map[string]*webmPlayer)
	}
	p := &webmPlayer{}
	c.players[msgID] = p
	return p
}

// publish installs a parsed animation and starts its clock + producer.
func (c *webmPlayerCache) publish(msgID, path string, anim *vp9anim.Animation) *vp9anim.Player {
	c.mu.Lock()
	defer c.mu.Unlock()
	p := c.players[msgID]
	if p == nil {
		p = &webmPlayer{}
		c.players[msgID] = p
	}
	p.anim, p.parsed, p.reading, p.failed = anim, true, false, false
	p.path = path
	pl := anim.NewPlayer()
	p.player = pl
	p.start = time.Now()
	pl.Start()
	return pl
}

// reset clears a parsed animation (new source file for the message).
func (c *webmPlayerCache) reset(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p := c.players[msgID]; p != nil {
		if p.player != nil {
			go p.player.Stop()
		}
		p.anim, p.player, p.parsed, p.path, p.failed, p.reading = nil, nil, false, "", false, false
	}
}

// failParse pins the message to the static fallback (no re-parse churn).
func (c *webmPlayerCache) failParse(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p := c.players[msgID]; p != nil {
		p.failed, p.reading = true, false
	}
}

// replay restarts the play clock from frame 0.
func (c *webmPlayerCache) replay(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p := c.players[msgID]; p != nil {
		p.start = time.Now()
	}
}

// markReading claims the async read slot; false while one is in flight.
func (c *webmPlayerCache) markReading(msgID string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	p := c.players[msgID]
	if p == nil {
		p = &webmPlayer{}
		c.players[msgID] = p
	}
	if p.reading {
		return false
	}
	p.reading = true
	return true
}

// endReading releases the read slot (retryable failures).
func (c *webmPlayerCache) endReading(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p := c.players[msgID]; p != nil {
		p.reading = false
	}
}

// ensureWebmPlayer kicks off the one-time async parse of a downloaded
// .webm sticker document; repaints when the first decoded frame lands.
func (a *App) ensureWebmPlayer(m *engine.CachedMessage) {
	if m == nil || m.MediaLocalPath == "" {
		return
	}
	p := webmPlayers.get(m.MsgID)
	if p.parsed && p.path != m.MediaLocalPath {
		// New file for the same message: re-parse.
		webmPlayers.reset(m.MsgID)
		p = webmPlayers.get(m.MsgID)
	}
	if p.parsed || p.failed {
		return
	}
	if !webmPlayers.markReading(m.MsgID) {
		return
	}
	msgID, path := m.MsgID, m.MediaLocalPath
	go func() {
		data, err := os.ReadFile(path)
		if err != nil {
			webmPlayers.endReading(msgID) // retry on a later frame
			return
		}
		anim, err := vp9anim.Parse(data)
		if err != nil || anim == nil || anim.FrameCount() == 0 {
			webmPlayers.failParse(msgID) // static fallback, permanently
			return
		}
		pl := webmPlayers.publish(msgID, path, anim)
		// Repaint once the first frame is decoded so the bubble swaps
		// from its thumbnail to the playing video.
		go func() {
			for i := 0; i < 400; i++ { // ≤ 2s at 5ms
				if pl.DecodedCount() >= 1 || pl.Failed() != nil {
					a.invalidate()
					return
				}
				time.Sleep(5 * time.Millisecond)
			}
		}()
	}()
}

// replayWebmSticker restarts a video sticker from frame 0 (tap action).
func (a *App) replayWebmSticker(m *engine.CachedMessage) {
	if m == nil {
		return
	}
	webmPlayers.replay(m.MsgID)
	a.invalidate()
}

// drawWebmSticker renders the current frame of a playing video sticker
// inside the maxSide box; false while the producer is still warming up
// (the caller falls back to the static thumbnail path).
func (a *App) drawWebmSticker(gtx layout.Context, m *engine.CachedMessage, maxSide int) (layout.Dimensions, bool) {
	e := webmPlayers.get(m.MsgID)
	if !e.parsed || e.anim == nil || e.player == nil {
		return layout.Dimensions{}, false
	}
	w, h := stickerBox(maxSide, e.anim.Width, e.anim.Height)
	if w <= 0 || h <= 0 {
		return layout.Dimensions{}, false
	}
	elapsed := time.Since(e.start)
	// Power saving (slice 135): the first frame renders statically with
	// no re-arm — loops are the battery cost.
	if powerSavingBlocks(powerSaving.flags, powerSaving.forceAll, psClassStickers) {
		if img := e.player.FrameAt(0); img != nil {
			return drawImageScaled(gtx, img, w, h, 0), true
		}
		return layout.Dimensions{Size: image.Pt(w, h)}, true
	}
	img := e.player.FrameAt(elapsed)
	if img == nil {
		// Producer warming up (or mid-loop reset): hold the box.
		return layout.Dimensions{}, false
	}
	dims := drawImageScaled(gtx, img, w, h, 0)
	gtx.Execute(op.InvalidateCmd{At: time.Now().Add(e.player.NextFrameIn(elapsed))})
	return dims, true
}

// drawWebmEmoji renders one inline video custom emoji at side×side from
// the shared per-document player (drawEmojiArt's video branch). Returns
// false when no frame is ready (base-glyph fallback for that paint).
func drawWebmEmoji(gtx layout.Context, e *emojiArt, side int) bool {
	if e == nil || e.player == nil || e.anim == nil {
		return false
	}
	// Power saving: first frame, no re-arm.
	if powerSavingBlocks(powerSaving.flags, powerSaving.forceAll, psClassEmoji) {
		if img := e.player.FrameAt(0); img != nil {
			drawImageScaled(gtx, img, side, side, 0)
			return true
		}
		return false
	}
	elapsed := time.Since(e.start)
	img := e.player.FrameAt(elapsed)
	if img == nil {
		return false
	}
	drawImageScaled(gtx, img, side, side, 0)
	gtx.Execute(op.InvalidateCmd{At: time.Now().Add(e.player.NextFrameIn(elapsed))})
	return true
}

// stopWebmEmojiPlayer stops a per-document video emoji player on cache
// eviction (async: a mid-decode Stop could stall the frame thread).
func stopWebmEmojiPlayer(e *emojiArt) {
	if e != nil && e.player != nil {
		go e.player.Stop()
	}
}
