package gui

import (
	"image/color"
	"sync"
	"testing"

	"golang.org/x/image/font"

	"uniclient/engine"
)

func TestShotRenderPipelineIsSerialized(t *testing.T) {
	shotMu.Lock()
	shotFaceCache = map[[3]bool]font.Face{}
	shotSmallFaceCache = nil
	shotMu.Unlock()

	msg := engine.CachedMessage{
		SenderName:    "Alice",
		SenderColorID: 3,
		ContentText:   "The quick brown fox jumps over the lazy dog — twice, for a wrap check.",
		Timestamp:     1737000000,
		ReplyPreview:  "Bob: a quoted reply line for the small face",
		ForwardFrom:   "Channel X",
	}
	msg.ContentRich = []byte(`[{"type":"bold","offset":4,"length":6},{"type":"italic","offset":35,"length":6},{"type":"code","offset":45,"length":4}]`)
	pal := shotPalette{
		bubble:    color.NRGBA{R: 0x18, G: 0x2C, B: 0x3A, A: 0xFF},
		bubbleOut: color.NRGBA{R: 0x2B, G: 0x5D, B: 0x7A, A: 0xFF},
		text:      color.NRGBA{R: 0xF0, G: 0xF4, B: 0xF8, A: 0xFF},
		dim:       color.NRGBA{R: 0x9A, G: 0xA8, B: 0xB4, A: 0xFF},
		accent:    color.NRGBA{R: 0x53, G: 0x8C, B: 0xF0, A: 0xFF},
	}

	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < 15; j++ {
				img, err := renderMessageShot(msg, pal)
				if err != nil {
					t.Errorf("render: %v", err)
					return
				}
				if img.Bounds().Dx() < 200 {
					t.Errorf("image too small: %dpx", img.Bounds().Dx())
					return
				}
			}
		}()
	}
	wg.Wait()
}
