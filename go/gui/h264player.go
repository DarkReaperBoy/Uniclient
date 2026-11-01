package gui

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

type noteAction int

const (
	noteActionViewer noteAction = iota
	noteActionDownload
	noteActionWait
	noteActionPlay
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

func noteTapAction(p *h264PlayerState, downloaded bool) noteAction {
	if !downloaded {
		return noteActionDownload
	}
	if p == nil {
		return noteActionWait
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

type h264Player struct {
	video  *h264vid.Video
	player *h264vid.Player
	path   string

	start  time.Time
	paused time.Duration

	playing bool
	parsed  bool
	failed  bool
	reading bool
	loop    bool
	src     io.Closer
}

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

type h264PlayerCache struct {
	mu      sync.Mutex
	players map[string]*h264Player
}

var h264Players = &h264PlayerCache{players: make(map[string]*h264Player)}

const h264PlayerMax = 48

func closeSrc(p *h264Player) {
	if p != nil && p.src != nil {
		src := p.src
		p.src = nil
		src.Close()
	}
}

func (c *h264PlayerCache) evictLocked() {
	for _, old := range c.players {
		stopH264Player(old)
		closeSrc(old)
	}
	c.players = make(map[string]*h264Player)
}

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

func (c *h264PlayerCache) peek(msgID string) (h264PlayerState, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	p, ok := c.players[msgID]
	if !ok {
		return h264PlayerState{}, false
	}
	return snapshot(p), true
}

func (c *h264PlayerCache) len() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return len(c.players)
}

func (c *h264PlayerCache) publish(msgID, path string, video *h264vid.Video, loop bool) *h264vid.Player {
	return c.publishWithSrc(msgID, path, video, loop, nil)
}

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
		stopH264Player(p)
	}
	closeSrc(p)
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

func (c *h264PlayerCache) pause(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p := c.players[msgID]; p != nil && p.playing {
		p.paused = time.Since(p.start)
		p.playing = false
	}
}

func (c *h264PlayerCache) resume(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	p := c.players[msgID]
	if p == nil || !p.parsed || p.playing {
		return
	}
	if p.video != nil && p.video.Total > 0 && p.paused >= p.video.Total {
		p.paused = 0
	}
	p.start = time.Now().Add(-p.paused)
	p.playing = true
}

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

func (c *h264PlayerCache) reset(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p := c.players[msgID]; p != nil {
		stopH264Player(p)
		closeSrc(p)
		p.video, p.player, p.path = nil, nil, ""
		p.parsed, p.failed, p.reading, p.playing = false, false, false, false
		p.loop = false
		p.paused = 0
	}
}

func (c *h264PlayerCache) resetAll() []string {
	c.mu.Lock()
	defer c.mu.Unlock()
	ids := make([]string, 0, len(c.players))
	for id, p := range c.players {
		stopH264Player(p)
		closeSrc(p)
		ids = append(ids, id)
		delete(c.players, id)
	}
	return ids
}

func (c *h264PlayerCache) markReading(msgID string) bool {
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
	if p.reading {
		return false
	}
	p.reading = true
	return true
}

func (c *h264PlayerCache) endReading(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p := c.players[msgID]; p != nil {
		p.reading = false
	}
}

func stopH264Player(p *h264Player) {
	if p != nil && p.player != nil {
		pl := p.player
		p.player = nil
		go pl.Stop()
	}
}

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
		if p.failed {
			notify()
		}
		return
	}
	if p.path != "" && p.path != path {
		h264Players.reset(msgID)
	}
	if !h264Players.markReading(msgID) {
		return
	}
	go func() {
		data, err := os.ReadFile(path)
		if err != nil {
			h264Players.endReading(msgID)
			notify()
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
		a.videoAudioPlay(acct, chat, msgID, path)
		a.invalidate()
		a.repaintOnFirstFrame(pl)
	}()
}

func (a *App) repaintOnFirstFrame(pl *h264vid.Player) {
	go func() {
		for i := 0; i < 400; i++ {
			if pl.DecodedCount() >= 1 || pl.Failed() != nil {
				a.invalidate()
				return
			}
			time.Sleep(5 * time.Millisecond)
		}
	}()
}

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
		closer = c
	}
	pl := h264Players.publishWithSrc(msgID, path, video, loop, closer)
	if pl == nil {
		return nil, errors.New("gui: streamed clip published no player")
	}
	return pl, nil
}

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
		h264Players.reset(msgID)
		p = h264PlayerState{}
	}
	if p.failed {
		closeRa()
		return false
	}
	if p.path == path && (p.parsed || p.reading) {
		closeRa()
		return true
	}
	if !h264Players.markReading(msgID) {
		closeRa()
		return true
	}
	go func() {
		pl, err := publishStreamedClip(msgID, path, ra, size, loop)
		if err != nil {
			h264Players.endReading(msgID)
			if h264vid.IsPermanent(err) {
				h264Players.failParse(msgID)
			}
			closeRa()
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

func (a *App) startVideoNoteInline(acct, chat, msgID, path string) {
	a.ensureH264Player(acct, chat, msgID, path, true, func() {
		a.setToast("Can't play this video in-app — opening system player")
		a.openMedia(path, true)
	})
}

func (a *App) tapVideoNote(m *engine.CachedMessage) bool {
	if m == nil || m.MediaLocalPath == "" {
		return false
	}
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
	default:
		return false
	}
}

func (a *App) setPlayOnDone(acct, chat, msg string, seq int) {
	a.mu.Lock()
	if a.playOnDone == nil {
		a.playOnDone = make(map[string]bool)
	}
	a.playOnDone[dlKey(acct, chat, msg, seq)] = true
	a.mu.Unlock()
}

func (a *App) consumePlayOnDone(acct, chat, msg string, seq int) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.consumePlayOnDoneLocked(acct, chat, msg, seq)
}

func (a *App) consumePlayOnDoneLocked(acct, chat, msg string, seq int) bool {
	if a.playOnDone == nil {
		return false
	}
	k := dlKey(acct, chat, msg, seq)
	v := a.playOnDone[k]
	delete(a.playOnDone, k)
	return v
}

func (a *App) drawVideoNoteFrame(gtx layout.Context, msgID string, diameter int) (layout.Dimensions, bool) {
	e, ok := h264Players.peek(msgID)
	if !ok || !e.playing || e.video == nil || e.player == nil || diameter <= 0 {
		return layout.Dimensions{}, false
	}
	if e.player.Failed() != nil {
		h264Players.reset(msgID)
		a.videoAudioPause(msgID)
		return layout.Dimensions{}, false
	}
	elapsed := h264Players.elapsed(msgID)

	if powerSavingBlocks(powerSaving.flags, powerSaving.forceAll, psClassVideo) {
		if img := e.player.FrameAt(elapsed); img != nil {
			return drawImageEllipse(gtx, img, diameter), true
		}
		return layout.Dimensions{Size: image.Pt(diameter, diameter)}, true
	}

	img := e.player.FrameAt(elapsed)
	if img == nil {
		return layout.Dimensions{}, false
	}
	a.videoAudioLoop(msgID)
	dims := drawImageEllipse(gtx, img, diameter)
	gtx.Execute(op.InvalidateCmd{At: time.Now().Add(e.player.NextFrameIn(elapsed))})
	return dims, true
}
