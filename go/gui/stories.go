package gui

// Stories (AyuGram parity slice 104): the chat list gains the horizontal
// story-circles row (unread first; accent ring for unseen, dim for seen)
// and the story viewer overlay — progress segments, tap zones, caption and
// views meta, video stories handed to the system player (in-app playback
// waits on engine streaming). All data comes from engine.FetchPeerStories;
// an honest loading state covers the fetch, an honest error card its
// failure (§1.10 — nothing simulated).

import (
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"strings"
	"time"

	"gioui.org/f32"
	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// storyItem mirrors the engine's FetchPeerStories JSON contract (the
// fields the viewer renders).
type storyItem struct {
	ID        int    `json:"id"`
	Date      int64  `json:"date"`
	Caption   string `json:"caption"`
	MediaType string `json:"media_type"`
	LocalPath string `json:"local_path"`
	Views     int    `json:"views"`
}

// storyViewerState is the open story viewer (slice 104).
type storyViewerState struct {
	accountID string
	chatID    string
	title     string
	items     []storyItem
	cur       int
	loading   bool
	err       string
}

// storyStripChats picks the chats that appear in the stories row — only
// chats with stories, unread first (AyuGram order).
func storyStripChats(chats []engine.ChatInfo) []engine.ChatInfo {
	var unread, seen []engine.ChatInfo
	for _, c := range chats {
		if c.StoryCount <= 0 {
			continue // zero-count + dangling unread flag stays hidden
		}
		if c.HasUnreadStory {
			unread = append(unread, c)
		} else {
			seen = append(seen, c)
		}
	}
	return append(unread, seen...)
}

// storyRingUnread: ring style keys off the chat's unread flag.
func storyRingUnread(c engine.ChatInfo) bool { return c.HasUnreadStory }

// parseStories decodes the engine's stories JSON.
func parseStories(s string) ([]storyItem, error) {
	var items []storyItem
	if err := json.Unmarshal([]byte(s), &items); err != nil {
		return nil, err
	}
	return items, nil
}

// isVideoStory: video media type or an .mp4 local path (the engine writes
// .mp4 for non-jpeg story media).
func isVideoStory(s storyItem) bool {
	return s.MediaType == "video" || strings.HasSuffix(strings.ToLower(s.LocalPath), ".mp4")
}

// storyStep clamps navigation (caller closes when stepping past the end).
func storyStep(cur, delta, n int) int {
	next := cur + delta
	if next < 0 {
		return 0
	}
	if next >= n {
		return n - 1
	}
	return next
}

// storyMetaLine renders the views/date line.
func storyMetaLine(s storyItem, now time.Time) string {
	var parts []string
	if s.Views > 0 {
		parts = append(parts, fmt.Sprintf("%d views", s.Views))
	}
	if s.Date > 0 {
		t := time.Unix(s.Date, 0)
		if t.Format("2006-01-02") == now.Format("2006-01-02") {
			parts = append(parts, t.Format("15:04"))
		} else {
			parts = append(parts, t.Format("2 Jan · 15:04"))
		}
	}
	return strings.Join(parts, " · ")
}

// ── state transitions ─────────────────────────────────────────────────────

var (
	storyStripList widget.List
	storyPrevBtn   widget.Clickable
	storyNextBtn   widget.Clickable
	storyCloseBtn  widget.Clickable
	storyPlayBtn   widget.Clickable
	storyTapL      = new(bool) // left tap zone
	storyTapR      = new(bool) // right tap zone
	storyKeyTag    = new(bool) // viewer keyboard layer
)

func init() {
	storyStripList.Axis = layout.Horizontal
}

// openStoryViewer fetches a chat's stories and opens the viewer (slice 104).
func (a *App) openStoryViewer(c engine.ChatInfo) {
	a.mu.Lock()
	a.storyView = &storyViewerState{
		accountID: c.AccountID,
		chatID:    c.ChatID,
		title:     c.Title,
		loading:   true,
	}
	a.mu.Unlock()
	a.invalidate()
	go func() {
		raw, err := a.eng.FetchPeerStories(c.AccountID, c.ChatID)
		a.mu.Lock()
		sv := a.storyView
		if sv == nil || sv.chatID != c.ChatID || sv.accountID != c.AccountID {
			a.mu.Unlock()
			return // a different viewer opened meanwhile
		}
		sv.loading = false
		if err != nil {
			sv.err = err.Error()
		} else {
			sv.items, err = parseStories(raw)
			if err != nil {
				sv.err = err.Error()
			}
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// closeStoryViewer dismisses the overlay.
func (a *App) closeStoryViewer() {
	a.mu.Lock()
	a.storyView = nil
	a.mu.Unlock()
	a.invalidate()
}

// storyAdvance steps the viewer; stepping past the last story closes it
// (AyuGram behavior).
func (a *App) storyAdvance(delta int) {
	a.mu.Lock()
	sv := a.storyView
	if sv == nil {
		a.mu.Unlock()
		return
	}
	sv.cur = storyStep(sv.cur, delta, len(sv.items))
	last := sv.cur >= len(sv.items)-1
	a.mu.Unlock()
	if delta > 0 && last {
		a.closeStoryViewer()
		return
	}
	a.invalidate()
}

// ── strip layout ──────────────────────────────────────────────────────────

// layoutStoryStrip renders the horizontal story circles above the chat
// list (AyuGram's stories row). Hidden entirely when no chat has stories.
func (a *App) layoutStoryStrip(gtx layout.Context, f frame) layout.Dimensions {
	chats := storyStripChats(f.chats)
	if len(chats) == 0 {
		return layout.Dimensions{}
	}
	return layout.Inset{Left: unit.Dp(10), Right: unit.Dp(10), Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		list := material.List(a.ui.Theme, &storyStripList)
		return list.Layout(gtx, len(chats), func(gtx layout.Context, i int) layout.Dimensions {
			c := chats[i]
			key := "story:" + c.AccountID + "/" + c.ChatID
			btn := storyStripBtn(key)
			if btn.Clicked(gtx) {
				if f.cfg.Streamer {
					a.setToast("Stories hidden in streamer mode")
				} else {
					go a.openStoryViewer(c) // GUI-safe: state set under lock
				}
			}
			return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return material.ButtonLayout(a.ui.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.storyCircle(gtx, f, c)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							gtx.Constraints.Max.X = gtx.Dp(unit.Dp(64))
							lbl := a.ui.Dim(unit.Sp(10), storyStripName(c.Title))
							lbl.Color = a.ui.p.TextDim
							if f.cfg.Streamer {
								return a.masked(gtx, lbl.Layout)
							}
							return lbl.Layout(gtx)
						})
					}),
				)
			})
		})
	})
}

// storyStripName clips long names to one line.
func storyStripName(name string) string {
	r := []rune(name)
	if len(r) > 9 {
		return string(r[:9]) + "…"
	}
	return name
}

// storyCircle renders one strip avatar with its story ring.
func (a *App) storyCircle(gtx layout.Context, f frame, c engine.ChatInfo) layout.Dimensions {
	size := unit.Dp(56)
	var d layout.Dimensions
	if img := a.avatarImage(c.AvatarPath, ""); img != nil {
		d = avatarFromImage(gtx, a, img, size, dotNone)
	} else {
		d = a.ui.Avatar(gtx, c.Title, size, dotNone)
	}
	// Ring: accent for unread stories, dim for seen (AyuGram).
	ringCol := a.ui.p.TextFaint
	if storyRingUnread(c) {
		ringCol = a.ui.p.Accent
	}
	paintRing(gtx, ringCol, d.Size.X, gtx.Dp(unit.Dp(2)))
	return d
}

// paintRing strokes a circular ring of the given color around size.
func paintRing(gtx layout.Context, c color.NRGBA, size int, w int) {
	if w < 1 {
		w = 1
	}
	pad := w / 2
	spec := clip.Ellipse{Min: image.Pt(pad, pad), Max: image.Pt(size-pad, size-pad)}.Path(gtx.Ops)
	stroke := clip.Stroke{Path: spec, Width: float32(w)}
	paint.FillShape(gtx.Ops, c, stroke.Op())
}

// storyStripBtn pools the strip clickables.
var storyStripBtns = map[string]*widget.Clickable{}

func storyStripBtn(key string) *widget.Clickable {
	if btn, ok := storyStripBtns[key]; ok {
		return btn
	}
	btn := new(widget.Clickable)
	storyStripBtns[key] = btn
	if len(storyStripBtns) > 128 {
		storyStripBtns = map[string]*widget.Clickable{key: btn}
	}
	return btn
}

// ── viewer layout ─────────────────────────────────────────────────────────

// layoutStoryViewer: full-window story playback overlay (slice 104).
func (a *App) layoutStoryViewer(gtx layout.Context, f frame) layout.Dimensions {
	sv := f.storyView
	gtx.Execute(key.FocusCmd{Tag: nil})

	// Keyboard: Esc closes, arrows navigate.
	{
		stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
		event.Op(gtx.Ops, storyKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(
			key.Filter{Name: key.NameEscape},
			key.Filter{Name: key.NameLeftArrow},
			key.Filter{Name: key.NameRightArrow},
		)
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			switch ke.Name {
			case key.NameEscape:
				a.closeStoryViewer()
			case key.NameLeftArrow:
				a.storyAdvance(-1)
			case key.NameRightArrow:
				a.storyAdvance(1)
			}
		}
	}

	// Backdrop.
	paintFill(gtx.Ops, color.NRGBA{R: 0x05, G: 0x08, B: 0x0C, A: 0xF6}, gtx.Constraints.Max)

	if storyCloseBtn.Clicked(gtx) {
		a.closeStoryViewer()
	}
	if storyPrevBtn.Clicked(gtx) {
		a.storyAdvance(-1)
	}
	if storyNextBtn.Clicked(gtx) {
		a.storyAdvance(1)
	}
	if storyPlayBtn.Clicked(gtx) {
		if it := sv.current(); it != nil && isVideoStory(*it) && it.LocalPath != "" {
			go a.openMedia(it.LocalPath, true) // system player (slice 86 pipeline)
		}
	}

	if sv.loading {
		return a.storyCentered(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(14), "Loading stories…")
			lbl.Color = a.ui.p.TextFaint
			return lbl.Layout(gtx)
		})
	}
	if sv.err != "" {
		return a.storyCentered(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(15), "Could not load stories")
					lbl.Color = a.ui.p.Error
					return lbl.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(12), sv.err)
						lbl.Color = a.ui.p.TextDim
						return lbl.Layout(gtx)
					})
				}),
			)
		})
	}
	if len(sv.items) == 0 {
		return a.storyCentered(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(14), "No stories")
			lbl.Color = a.ui.p.TextFaint
			return lbl.Layout(gtx)
		})
	}

	it := sv.current()

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		// Progress segments + title + close.
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(12), Left: unit.Dp(16), Right: unit.Dp(16)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.storyProgress(gtx, sv)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
										if img := a.avatarImage(storyChatAvatarPath(f, sv), ""); img != nil {
											return avatarFromImage(gtx, a, img, unit.Dp(28), dotNone)
										}
										return a.ui.Avatar(gtx, sv.title, unit.Dp(28), dotNone)
									})
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Label(unit.Sp(14), sv.title)
									lbl.Color = color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF}
									if f.cfg.Streamer {
										return a.masked(gtx, lbl.Layout)
									}
									return lbl.Layout(gtx)
								}),
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									return layout.Dimensions{}
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.IconButton(&storyCloseBtn, iconContentClear, "Close")
									btn.Color = a.ui.p.TextDim
									return btn.Layout(gtx)
								}),
							)
						})
					}),
				)
			})
		}),
		// Media area + tap zones.
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
				layout.Flexed(0.2, func(gtx layout.Context) layout.Dimensions {
					// Left tap zone: previous story.
					for {
						ev, ok := gtx.Source.Event(pointer.Filter{Target: storyTapL, Kinds: pointer.Press})
						if !ok {
							break
						}
						if _, is := ev.(pointer.Event); is {
							a.storyAdvance(-1)
						}
					}
					stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
					event.Op(gtx.Ops, storyTapL)
					stack.Pop()
					return layout.Dimensions{Size: gtx.Constraints.Max}
				}),
				layout.Flexed(0.6, func(gtx layout.Context) layout.Dimensions {
					return a.storyMedia(gtx, f, sv, it)
				}),
				layout.Flexed(0.2, func(gtx layout.Context) layout.Dimensions {
					// Right tap zone: next story / close past the last.
					for {
						ev, ok := gtx.Source.Event(pointer.Filter{Target: storyTapR, Kinds: pointer.Press})
						if !ok {
							break
						}
						if _, is := ev.(pointer.Event); is {
							a.storyAdvance(1)
						}
					}
					stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
					event.Op(gtx.Ops, storyTapR)
					stack.Pop()
					return layout.Dimensions{Size: gtx.Constraints.Max}
				}),
			)
		}),
		// Caption + meta.
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Left: unit.Dp(24), Right: unit.Dp(24), Bottom: unit.Dp(20)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if it == nil || strings.TrimSpace(it.Caption) == "" {
							return layout.Dimensions{}
						}
						lbl := a.ui.Label(unit.Sp(15), it.Caption)
						lbl.Color = color.NRGBA{R: 0xF2, G: 0xF5, B: 0xF7, A: 0xFF}
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if it == nil {
							return layout.Dimensions{}
						}
						meta := storyMetaLine(*it, f.now)
						if meta == "" {
							return layout.Dimensions{}
						}
						return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(12), meta)
							lbl.Color = a.ui.p.TextDim
							return lbl.Layout(gtx)
						})
					}),
				)
			})
		}),
	)
}

// current returns the active story (nil-safe).
func (sv *storyViewerState) current() *storyItem {
	if sv == nil || sv.cur < 0 || sv.cur >= len(sv.items) {
		return nil
	}
	return &sv.items[sv.cur]
}

// storyChatAvatarPath resolves the viewer header avatar path.
func storyChatAvatarPath(f frame, sv *storyViewerState) string {
	for _, c := range f.chats {
		if c.AccountID == sv.accountID && c.ChatID == sv.chatID {
			return c.AvatarPath
		}
	}
	return ""
}

// storyProgress renders the segment bar (one per story, active accent).
func (a *App) storyProgress(gtx layout.Context, sv *storyViewerState) layout.Dimensions {
	n := len(sv.items)
	if n == 0 {
		return layout.Dimensions{}
	}
	h := gtx.Dp(unit.Dp(3))
	w := gtx.Constraints.Max.X / n
	children := make([]layout.FlexChild, 0, n)
	for i := 0; i < n; i++ {
		i := i
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			c := color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0x40}
			if i == sv.cur {
				c = a.ui.p.Accent
			}
			defer clip.Rect{Max: image.Pt(w, h)}.Push(gtx.Ops).Pop()
			paint.Fill(gtx.Ops, c)
			return layout.Dimensions{Size: image.Pt(w, h)}
		}))
	}
	return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, children...)
}

// storyMedia renders the current story's media: image inline (async
// decode), video via an honest card + system-player handoff.
func (a *App) storyMedia(gtx layout.Context, f frame, sv *storyViewerState, it *storyItem) layout.Dimensions {
	if it == nil {
		return layout.Dimensions{}
	}
	if isVideoStory(*it) {
		return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					gtx.Constraints.Max.X = gtx.Dp(unit.Dp(48))
					gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(48))
					return iconAVVideocam.Layout(gtx, a.ui.p.TextDim)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(13), "Video story")
						lbl.Color = a.ui.p.TextFaint
						return lbl.Layout(gtx)
					})
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if it.LocalPath == "" {
						return layout.Dimensions{}
					}
					return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.PrimaryButton(&storyPlayBtn, "PLAY IN SYSTEM PLAYER")
						return btn.Layout(gtx)
					})
				}),
			)
		})
	}
	if it.LocalPath == "" || !isDisplayableImage(it.LocalPath) {
		return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(13), "Story media unavailable")
			lbl.Color = a.ui.p.TextFaint
			return lbl.Layout(gtx)
		})
	}
	var img *image.RGBA
	k := "file:" + it.LocalPath
	if img = mediaImgs.get(k); img == nil {
		a.decodeFileAsync(it.LocalPath)
	}
	if img == nil {
		// Still decoding: stable box.
		return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return roundedFill(gtx, color.NRGBA{A: 0x20}, 12, func(gtx layout.Context) layout.Dimensions {
				w := gtx.Dp(unit.Dp(240))
				return layout.Dimensions{Size: image.Pt(w, w)}
			})
		})
	}
	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		w0, h0 := img.Bounds().Dx(), img.Bounds().Dy()
		boxW, boxH := gtx.Constraints.Max.X, gtx.Constraints.Max.Y
		scale := 1.0
		if w0 > 0 && h0 > 0 {
			sw, sh := float64(boxW)/float64(w0), float64(boxH)/float64(h0)
			scale = sw
			if sh < scale {
				scale = sh
			}
			if scale > 1 {
				scale = 1
			}
		}
		w, h := float32(w0)*float32(scale), float32(h0)*float32(scale)
		clipStack := clip.Rect{Max: image.Pt(int(w), int(h))}.Push(gtx.Ops)
		trStack := op.Affine(f32.AffineId().
			Scale(f32.Point{}, f32.Pt(float32(scale), float32(scale)))).Push(gtx.Ops)
		imgOp := paint.NewImageOp(img)
		imgOp.Filter = paint.FilterLinear
		imgOp.Add(gtx.Ops)
		paint.PaintOp{}.Add(gtx.Ops)
		trStack.Pop()
		clipStack.Pop()
		return layout.Dimensions{Size: image.Pt(int(w), int(h))}
	})
}

// storyCentered is the loading/error/empty card.
func (a *App) storyCentered(gtx layout.Context, w layout.Widget) layout.Dimensions {
	return layout.Center.Layout(gtx, w)
}
