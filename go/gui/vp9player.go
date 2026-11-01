package gui

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

type webmPlayer struct {
	anim    *vp9anim.Animation
	player  *vp9anim.Player
	start   time.Time
	path    string
	parsed  bool
	failed  bool
	reading bool
}

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

func (c *webmPlayerCache) failParse(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p := c.players[msgID]; p != nil {
		p.failed, p.reading = true, false
	}
}

func (c *webmPlayerCache) replay(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p := c.players[msgID]; p != nil {
		p.start = time.Now()
	}
}

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

func (c *webmPlayerCache) endReading(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p := c.players[msgID]; p != nil {
		p.reading = false
	}
}

func (a *App) ensureWebmPlayer(m *engine.CachedMessage) {
	if m == nil || m.MediaLocalPath == "" {
		return
	}
	p := webmPlayers.get(m.MsgID)
	if p.parsed && p.path != m.MediaLocalPath {
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
			webmPlayers.endReading(msgID)
			return
		}
		anim, err := vp9anim.Parse(data)
		if err != nil || anim == nil || anim.FrameCount() == 0 {
			webmPlayers.failParse(msgID)
			return
		}
		pl := webmPlayers.publish(msgID, path, anim)
		go func() {
			for i := 0; i < 400; i++ {
				if pl.DecodedCount() >= 1 || pl.Failed() != nil {
					a.invalidate()
					return
				}
				time.Sleep(5 * time.Millisecond)
			}
		}()
	}()
}

func (a *App) replayWebmSticker(m *engine.CachedMessage) {
	if m == nil {
		return
	}
	webmPlayers.replay(m.MsgID)
	a.invalidate()
}

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
	if powerSavingBlocks(powerSaving.flags, powerSaving.forceAll, psClassStickers) {
		if img := e.player.FrameAt(0); img != nil {
			return drawImageScaled(gtx, img, w, h, 0), true
		}
		return layout.Dimensions{Size: image.Pt(w, h)}, true
	}
	img := e.player.FrameAt(elapsed)
	if img == nil {
		return layout.Dimensions{}, false
	}
	dims := drawImageScaled(gtx, img, w, h, 0)
	gtx.Execute(op.InvalidateCmd{At: time.Now().Add(e.player.NextFrameIn(elapsed))})
	return dims, true
}

func drawWebmEmoji(gtx layout.Context, e *emojiArt, side int) bool {
	if e == nil || e.player == nil || e.anim == nil {
		return false
	}
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
