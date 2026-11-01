package gui

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"uniclient/h264vid"
)

type countCloser struct {
	data   []byte
	closed atomic.Int32
}

func (c *countCloser) ReadAt(p []byte, off int64) (int, error) {
	if off >= int64(len(c.data)) {
		return 0, io.EOF
	}
	return copy(p, c.data[off:]), nil
}

func (c *countCloser) Close() error {
	c.closed.Add(1)
	return nil
}

func (c *countCloser) isClosed() bool { return c.closed.Load() > 0 }

func fixtureBytes(t *testing.T) []byte {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("..", "h264vid", "testdata", "round_video.mp4"))
	if err != nil {
		t.Skipf("h264vid fixture missing: %v", err)
	}
	return data
}

func TestEnsureStreamPlayerClosesDeclinedReader(t *testing.T) {
	data := fixtureBytes(t)
	const path = "/media/a1/full/decline_0.mp4"
	size := int64(len(data))

	t.Run("already parsed same path", func(t *testing.T) {
		const m = "decline-parsed"
		t.Cleanup(func() { h264Players.reset(m) })
		if _, err := publishStreamedClip(m, path, bytes.NewReader(data), size, true); err != nil {
			t.Fatal(err)
		}
		cc := &countCloser{data: data}
		if !ensureH264StreamPlayerForTest(m, path, cc, size) {
			t.Error("ensure declined an already-playing clip (caller would fall back and re-download)")
		}
		if !cc.isClosed() {
			t.Error("declined duplicate reader leaked — every re-open of a playing clip cost an fd")
		}
	})

	t.Run("permanently failed file", func(t *testing.T) {
		const m = "decline-failed"
		h264Players.failParse(m)
		t.Cleanup(func() { h264Players.reset(m) })
		cc := &countCloser{data: data}
		if ensureH264StreamPlayerForTest(m, path, cc, size) {
			t.Error("ensure accepted a permanently failed file — the tap would do nothing (dead bubble, §1.10)")
		}
		if !cc.isClosed() {
			t.Error("reader leaked on the failed decline")
		}
	})

	t.Run("parse already in flight elsewhere", func(t *testing.T) {
		const m = "decline-reading"
		if !h264Players.markReading(m) {
			t.Fatal("seed markReading")
		}
		t.Cleanup(func() { h264Players.reset(m) })
		cc := &countCloser{data: data}
		if !ensureH264StreamPlayerForTest(m, path, cc, size) {
			t.Error("ensure declined while another parse owns the entry")
		}
		if !cc.isClosed() {
			t.Error("reader leaked when the parse slot was already taken")
		}
	})

	t.Run("invalid arguments", func(t *testing.T) {
		cc := &countCloser{data: data}
		if ensureH264StreamPlayerForTest("", path, cc, size) {
			t.Error("accepted an empty msgID")
		}
		if !cc.isClosed() {
			t.Error("reader leaked on the invalid-argument decline")
		}
	})
}

func ensureH264StreamPlayerForTest(msgID, path string, ra io.ReaderAt, size int64) bool {
	a := &App{}
	return a.ensureH264StreamPlayer(msgID, path, ra, size, true)
}

func TestEnsureStreamPlayerClosesReaderOnParseFailure(t *testing.T) {
	const m = "fail-closes"
	const path = "/media/a1/full/fail-closes_0.mp4"
	t.Cleanup(func() { h264Players.reset(m) })

	cc := &countCloser{data: []byte("definitely not an mp4")}
	var fired atomic.Int32
	a := &App{}
	if !a.ensureH264StreamPlayer(m, path, cc, int64(len(cc.data)), true, func() { fired.Add(1) }) {
		t.Fatal("ensure declined before attempting the parse")
	}
	waitFor(t, "parse failure closes the reader", func() bool { return cc.isClosed() })
	waitFor(t, "fallback ran exactly once", func() bool { return fired.Load() == 1 })
	waitFor(t, "reading slot released", func() bool {
		st, ok := h264Players.peek(m)
		return ok && !st.reading
	})

	st, ok := h264Players.peek(m)
	if !ok {
		t.Fatal("no entry after failure")
	}
	if st.failed {
		t.Error("decode-stage failure pinned the entry permanent — a transient short read would dead-end the clip")
	}
	if st.parsed {
		t.Errorf("parsed=true after a failed parse")
	}
	time.Sleep(50 * time.Millisecond)
	if fired.Load() != 1 {
		t.Errorf("onFail ran %d times, want exactly 1", fired.Load())
	}
}

func TestStreamSourceClosesOnResetReplaceEviction(t *testing.T) {
	data := fixtureBytes(t)
	size := int64(len(data))

	t.Run("reset closes", func(t *testing.T) {
		const m = "src-reset"
		cc := &countCloser{data: data}
		if _, err := publishStreamedClip(m, "/p/a.mp4", cc, size, true); err != nil {
			t.Fatal(err)
		}
		if cc.isClosed() {
			t.Fatal("reader closed while the player is live")
		}
		h264Players.reset(m)
		if !cc.isClosed() {
			t.Error("reset dropped the entry without closing its stream reader")
		}
	})

	t.Run("replace closes the old source", func(t *testing.T) {
		const m = "src-replace"
		t.Cleanup(func() { h264Players.reset(m) })
		cc := &countCloser{data: data}
		if _, err := publishStreamedClip(m, "/p/old.mp4", cc, size, true); err != nil {
			t.Fatal(err)
		}
		if _, err := publishStreamedClip(m, "/p/new.mp4", bytes.NewReader(data), size, true); err != nil {
			t.Fatal(err)
		}
		if !cc.isClosed() {
			t.Error("re-publish replaced the reader without closing the old one")
		}
	})

	t.Run("eviction closes every streamed entry", func(t *testing.T) {
		cc := &countCloser{data: data}
		if _, err := publishStreamedClip("evict-victim", "/p/v.mp4", cc, size, true); err != nil {
			t.Fatal(err)
		}
		var fillers []string
		for i := 0; i < h264PlayerMax; i++ {
			id := "evict-filler-" + string(rune('a'+i%26)) + string(rune('0'+i/26))
			if !h264Players.markReading(id) {
				t.Fatalf("markReading(%q) refused", id)
			}
			fillers = append(fillers, id)
		}
		t.Cleanup(func() {
			for _, id := range fillers {
				h264Players.reset(id)
			}
			h264Players.reset("evict-victim")
		})
		if !h264Players.markReading("evict-trigger") {
			t.Fatal("markReading(trigger) refused")
		}
		t.Cleanup(func() { h264Players.reset("evict-trigger") })
		if !cc.isClosed() {
			t.Error("cache overflowed without closing the streamed entry's reader — fds grow for the whole session")
		}
	})
}

func TestStreamJoinAt(t *testing.T) {
	const path = "/media/a1/full/m1_0.mp4"
	total := 2400 * time.Millisecond
	vid := &h264vid.Video{Total: total}

	cases := []struct {
		name    string
		st      h264PlayerState
		have    bool
		local   string
		elapsed time.Duration
		wantOK  bool
		wantAt  time.Duration
	}{
		{
			name: "viewer clip mid-play joins at its playhead",
			st:   h264PlayerState{parsed: true, playing: true, path: path, video: vid},
			have: true, local: path, elapsed: time.Second,
			wantOK: true, wantAt: time.Second,
		},
		{
			name: "looping note wraps its join offset with the picture",
			st:   h264PlayerState{parsed: true, playing: true, path: path, video: vid, loop: true},
			have: true, local: path, elapsed: total + 600*time.Millisecond,
			wantOK: true, wantAt: 600 * time.Millisecond,
		},
		{
			name: "viewer clip that already played through gets NO orphan sound",
			st:   h264PlayerState{parsed: true, playing: true, path: path, video: vid},
			have: true, local: path, elapsed: total + time.Second,
			wantOK: false,
		},
		{
			name: "paused picture must not start sound",
			st:   h264PlayerState{parsed: true, playing: false, path: path, video: vid},
			have: true, local: path, elapsed: time.Second,
			wantOK: false,
		},
		{
			name: "different path is not our stream",
			st:   h264PlayerState{parsed: true, playing: true, path: path, video: vid},
			have: true, local: "/other.mp4", elapsed: time.Second,
			wantOK: false,
		},
		{
			name: "no player entry",
			st:   h264PlayerState{},
			have: false, local: path, elapsed: time.Second,
			wantOK: false,
		},
		{
			name: "parsed but no video timeline",
			st:   h264PlayerState{parsed: true, playing: true, path: path},
			have: true, local: path, elapsed: time.Second,
			wantOK: false,
		},
		{
			name: "duration-less video cannot place sound",
			st:   h264PlayerState{parsed: true, playing: true, path: path, video: &h264vid.Video{}},
			have: true, local: path, elapsed: time.Second,
			wantOK: false,
		},
	}
	for _, c := range cases {
		at, ok := streamJoinAt(c.st, c.have, c.local, c.elapsed)
		if ok != c.wantOK {
			t.Errorf("%s: ok = %v, want %v", c.name, ok, c.wantOK)
			continue
		}
		if ok && at != c.wantAt {
			t.Errorf("%s: join at %v, want %v", c.name, at, c.wantAt)
		}
	}
}
