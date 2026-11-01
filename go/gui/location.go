package gui

import (
	"bytes"
	"encoding/json"
	"fmt"
	"image"
	"strconv"
	"strings"
	"sync"
	"time"

	_ "image/png"

	"gioui.org/f32"
	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

type geoData struct {
	Lat     float64
	Long    float64
	Live    bool
	Period  int
	AccHash int64
	Venue   string
	Address string
}

func parseGeoMessage(m *engine.CachedMessage) *geoData {
	if m == nil || len(m.ContentRaw) == 0 {
		return nil
	}
	if !bytes.Contains(m.ContentRaw, []byte(`"geo_lat"`)) {
		return nil
	}
	var env rawEnvelope
	if err := json.Unmarshal(m.ContentRaw, &env); err != nil || env.Extra == nil {
		return nil
	}
	lat, ok1 := extraNum(env.Extra["geo_lat"])
	lon, ok2 := extraNum(env.Extra["geo_long"])
	if !ok1 || !ok2 {
		return nil
	}
	d := &geoData{Lat: lat, Long: lon}
	d.Live, _ = env.Extra["geo_live"].(bool)
	if p, ok := extraNum(env.Extra["geo_period"]); ok {
		d.Period = int(p)
	}
	if h, ok := extraNum(env.Extra["geo_access_hash"]); ok {
		d.AccHash = int64(h)
	}
	d.Venue = strVal(env.Extra["venue_title"])
	d.Address = strVal(env.Extra["venue_address"])
	return d
}

func (g *geoData) mapsURL() string {
	if g == nil {
		return ""
	}
	return fmt.Sprintf("https://maps.google.com/?q=%.6f,%.6f", g.Lat, g.Long)
}

func (g *geoData) coordLabel() string {
	if g == nil {
		return ""
	}
	return fmt.Sprintf("%.6f, %.6f", g.Lat, g.Long)
}

type contactData struct {
	Phone     string
	FirstName string
	LastName  string
	UserID    string
}

func parseContactMessage(m *engine.CachedMessage) *contactData {
	if m == nil || len(m.ContentRaw) == 0 {
		return nil
	}
	if !bytes.Contains(m.ContentRaw, []byte(`"contact_phone"`)) {
		return nil
	}
	var env rawEnvelope
	if err := json.Unmarshal(m.ContentRaw, &env); err != nil || env.Extra == nil {
		return nil
	}
	d := &contactData{
		Phone:     strVal(env.Extra["contact_phone"]),
		FirstName: strVal(env.Extra["contact_first_name"]),
		LastName:  strVal(env.Extra["contact_last_name"]),
		UserID:    strVal(env.Extra["contact_user_id"]),
	}
	if d.Phone == "" && d.FirstName == "" && d.LastName == "" {
		return nil
	}
	return d
}

func (c *contactData) fullName() string {
	if c == nil {
		return ""
	}
	return strings.TrimSpace(c.FirstName + " " + c.LastName)
}

func splitContactName(name string) (string, string) {
	name = strings.TrimSpace(name)
	if name == "" {
		return "", ""
	}
	parts := strings.Fields(name)
	if len(parts) == 1 {
		return parts[0], ""
	}
	return parts[0], strings.Join(parts[1:], " ")
}

func parseCoords(lat, lon string) (float64, float64, error) {
	la, err := strconv.ParseFloat(strings.TrimSpace(lat), 64)
	if err != nil {
		return 0, 0, fmt.Errorf("latitude")
	}
	lo, err := strconv.ParseFloat(strings.TrimSpace(lon), 64)
	if err != nil {
		return 0, 0, fmt.Errorf("longitude")
	}
	return la, lo, nil
}

const (
	mapTileW    = 440
	mapTileH    = 220
	mapTileZoom = 15
)

type mapTileCache struct {
	mu     sync.Mutex
	tiles  map[string]*image.RGBA
	busy   map[string]bool
	failed map[string]bool
}

var mapTiles = &mapTileCache{
	tiles:  make(map[string]*image.RGBA),
	busy:   make(map[string]bool),
	failed: make(map[string]bool),
}

func mapTileKey(g *geoData) string {
	if g == nil {
		return ""
	}
	return fmt.Sprintf("map:%.6f,%.6f:%d:%d:%d", g.Lat, g.Long, mapTileW, mapTileH, mapTileZoom)
}

func (c *mapTileCache) get(key string) *image.RGBA {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.tiles[key]
}

func (c *mapTileCache) claim(key string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.busy[key] || c.failed[key] || c.tiles[key] != nil {
		return false
	}
	c.busy[key] = true
	return true
}

func (c *mapTileCache) store(key string, img *image.RGBA) {
	c.mu.Lock()
	c.tiles[key], c.busy[key] = img, false
	c.mu.Unlock()
}

func (c *mapTileCache) fail(key string) {
	c.mu.Lock()
	c.busy[key], c.failed[key] = false, true
	c.mu.Unlock()
}

func (a *App) ensureMapTile(f frame, m *engine.CachedMessage, g *geoData) {
	if g == nil || f.selected == nil {
		return
	}
	key := mapTileKey(g)
	if key == "" || mapTiles.get(key) != nil {
		return
	}
	if !mapTiles.claim(key) {
		return
	}
	acc := f.selected.AccountID
	lat, long, hash := g.Lat, g.Long, g.AccHash
	go func() {
		data, err := a.eng.GetMapTile(acc, lat, long, hash, mapTileW, mapTileH, mapTileZoom)
		if err != nil || len(data) == 0 {
			mapTiles.fail(key)
			return
		}
		img, _, derr := decodeGUIImage(data)
		if derr != nil {
			mapTiles.fail(key)
			return
		}
		rgba, ok := img.(*image.RGBA)
		if !ok {
			rgba = imageToRGBA(img)
		}
		mapTiles.store(key, rgba)
		a.invalidate()
	}()
}

func imageToRGBA(img image.Image) *image.RGBA {
	b := img.Bounds()
	out := image.NewRGBA(image.Rect(0, 0, b.Dx(), b.Dy()))
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			out.Set(x-b.Min.X, y-b.Min.Y, img.At(x, y))
		}
	}
	return out
}

func drawTileCover(gtx layout.Context, img *image.RGBA, w, h int) layout.Dimensions {
	if img == nil || w <= 0 || h <= 0 || img.Bounds().Empty() {
		return layout.Dimensions{}
	}
	sx := float32(w) / float32(img.Bounds().Dx())
	sy := float32(h) / float32(img.Bounds().Dy())
	s := sx
	if sy > sx {
		s = sy
	}
	clipStack := clip.UniformRRect(image.Rectangle{Max: image.Pt(w, h)}, 10).Push(gtx.Ops)
	trStack := op.Affine(f32.AffineId().Scale(f32.Point{}, f32.Pt(s, s))).Push(gtx.Ops)
	imgOp := paint.NewImageOp(img)
	imgOp.Filter = paint.FilterLinear
	imgOp.Add(gtx.Ops)
	paint.PaintOp{}.Add(gtx.Ops)
	trStack.Pop()
	clipStack.Pop()
	return layout.Dimensions{Size: image.Pt(w, h)}
}

func (a *App) locationBubble(gtx layout.Context, f frame, m *engine.CachedMessage) layout.Dimensions {
	g := parseGeoMessage(m)
	w := gtx.Dp(unit.Dp(220))
	h := gtx.Dp(unit.Dp(110))
	gtx.Constraints = layout.Constraints{Max: image.Pt(w, h), Min: image.Pt(w, h)}
	a.ensureMapTile(f, m, g)
	var tile *image.RGBA
	if key := mapTileKey(g); key != "" {
		tile = mapTiles.get(key)
	}
	sub := ""
	if g != nil {
		if g.Address != "" {
			sub = g.Address
		} else {
			sub = g.coordLabel()
		}
	}
	mkey := m.AccountID + "|" + m.ChatID + "|" + m.MsgID
	stopBtn := a.liveStopClickable(mkey)
	ownLive := g != nil && g.Live && m.IsOutgoing
	if ownLive && stopBtn.Clicked(gtx) {
		go func() {
			if err := a.eng.StopLiveLocation(m.AccountID, m.ChatID, m.MsgID); err != nil {
				a.setToast("Stop live location failed: " + err.Error())
				return
			}
			a.setToast("Live location stopped")
		}()
	}
	if g != nil && g.Live && g.Period > 0 && liveAge(time.Now().Unix(), m.Timestamp) < g.Period {
		gtx.Execute(op.InvalidateCmd{At: time.Now().Add(30 * time.Second)})
	}

	return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
		return layout.Stack{}.Layout(gtx,
			layout.Expanded(func(gtx layout.Context) layout.Dimensions {
				if tile != nil {
					return drawTileCover(gtx, tile, w, h)
				}
				return layout.Dimensions{}
			}),
			layout.Stacked(func(gtx layout.Context) layout.Dimensions {
				if ownLive {
					return layout.Inset{Top: unit.Dp(6), Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						btn := material.Button(a.ui.Theme, stopBtn, "stop")
						btn.CornerRadius = 8
						btn.TextSize = unit.Sp(10)
						btn.Inset = layout.UniformInset(unit.Dp(4))
						btn.Background = a.ui.p.Accent
						return btn.Layout(gtx)
					})
				}
				return a.overlayBadge(gtx, liveBadgeText(g, m.Timestamp, time.Now().Unix()))
			}),
			layout.Stacked(func(gtx layout.Context) layout.Dimensions {
				if tile != nil {
					return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Top: unit.Dp(26)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								if iconMapsPlace != nil {
									sz := gtx.Dp(unit.Dp(22))
									gtx.Constraints = layout.Constraints{Max: image.Pt(sz, sz)}
									return iconMapsPlace.Layout(gtx, a.ui.p.Accent)
								}
								lbl := a.ui.Label(unit.Sp(20), "\U0001F4CD")
								return lbl.Layout(gtx)
							})
						}),
					)
				}
				caption := "Location"
				if g != nil && g.Venue != "" {
					caption = g.Venue
				}
				return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							if iconMapsPlace != nil {
								sz := gtx.Dp(unit.Dp(30))
								gtx.Constraints = layout.Constraints{Max: image.Pt(sz, sz)}
								return iconMapsPlace.Layout(gtx, a.ui.p.Accent)
							}
							lbl := a.ui.Label(unit.Sp(26), "\U0001F4CD")
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(14), caption)
							lbl.Color = a.ui.p.Text
							lbl.MaxLines = 1
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(11), sub)
							lbl.Color = a.ui.p.TextFaint
							lbl.MaxLines = 1
							return lbl.Layout(gtx)
						})
					}),
				)
			}),
			layout.Stacked(func(gtx layout.Context) layout.Dimensions {
				if tile == nil || sub == "" {
					return layout.Dimensions{}
				}
				return layout.Inset{Bottom: unit.Dp(6), Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return roundedFill(gtx, a.ui.p.Background, 8, func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3), Left: unit.Dp(8), Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(10), sub)
							lbl.MaxLines = 1
							return lbl.Layout(gtx)
						})
					})
				})
			}),
		)
	})
}

func (a *App) overlayBadge(gtx layout.Context, text string) layout.Dimensions {
	if text == "" {
		return layout.Dimensions{}
	}
	in := layout.Inset{Top: unit.Dp(6), Right: unit.Dp(6)}
	return in.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Accent, 8, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(4)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(10), text)
				lbl.Color = a.ui.p.Background
				return lbl.Layout(gtx)
			})
		})
	})
}

func liveBadgeText(g *geoData, msgTs, now int64) string {
	if g == nil || !g.Live {
		return ""
	}
	if g.Period > 0 {
		return liveRemainingText(g.Period, liveAge(now, msgTs))
	}
	return "live"
}

func liveAge(now, msgTs int64) int {
	if now <= msgTs {
		return 0
	}
	return int(now - msgTs)
}

func liveRemainingText(period, ageSec int) string {
	if period <= 0 {
		return "live"
	}
	remaining := period - ageSec
	if remaining <= 0 {
		return "ended"
	}
	return "live · " + itoa((remaining+59)/60) + "m left"
}

type liveDurationChoice struct {
	minutes int
	label   string
}

var liveDurationChoices = []liveDurationChoice{
	{15, "15 minutes"},
	{60, "1 hour"},
	{480, "8 hours"},
}

func (a *App) liveStopClickable(key string) *widget.Clickable {
	if c, ok := a.wid.liveStopBtns[key]; ok {
		return c
	}
	if len(a.wid.liveStopBtns) > 256 {
		a.wid.liveStopBtns = make(map[string]*widget.Clickable)
	}
	c := new(widget.Clickable)
	a.wid.liveStopBtns[key] = c
	return c
}

func (a *App) contactBubble(gtx layout.Context, m *engine.CachedMessage) layout.Dimensions {
	c := parseContactMessage(m)
	name := c.fullName()
	if name == "" {
		name = "Contact"
	}
	phone := ""
	if c != nil {
		phone = c.Phone
	}
	w := gtx.Dp(unit.Dp(220))
	return layout.Inset{}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = w
		return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						sz := gtx.Dp(unit.Dp(40))
						paint.FillShape(gtx.Ops, a.ui.p.Surface, clip.Ellipse{
							Min: image.Pt(0, 0), Max: image.Pt(sz, sz),
						}.Op(gtx.Ops))
						if iconSocialPerson != nil {
							inset := layout.Inset{
								Top: unit.Dp(8), Bottom: unit.Dp(8),
								Left: unit.Dp(8), Right: unit.Dp(8),
							}
							return inset.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								gtx.Constraints = layout.Constraints{Max: image.Pt(sz-sz/4, sz-sz/4)}
								return iconSocialPerson.Layout(gtx, a.ui.p.Accent)
							})
						}
						return layout.Dimensions{Size: image.Pt(sz, sz)}
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Label(unit.Sp(14), name)
									return lbl.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									if phone == "" {
										return layout.Dimensions{}
									}
									lbl := a.ui.Dim(unit.Sp(12), phone)
									lbl.Color = a.ui.p.TextDim
									return lbl.Layout(gtx)
								}),
							)
						})
					}),
				)
			})
		})
	})
}

type attachDlgState struct {
	kind     string
	account  string
	contacts []engine.ContactInfo
	loaded   bool
	err      string
}

var (
	attachDlgKeyTag = new(struct{})
)

func (a *App) openAttachDialog(kind string) {
	a.attachLiveOn = false
	a.attachLiveSel = 0
	a.mu.Lock()
	account := ""
	if a.selected != nil {
		account = a.selected.AccountID
	}
	var st *attachDlgState
	if account != "" {
		st = &attachDlgState{kind: kind, account: account}
	}
	a.attachDlg = st
	a.mu.Unlock()
	a.invalidate()
	if st != nil && kind == "contact" {
		go func() {
			contacts, err := a.eng.GetContacts(account)
			a.attachContactsDone(account, kind, contacts, err)
		}()
	}
}

func (a *App) attachContactsDone(account, kind string, contacts []engine.ContactInfo, err error) {
	if !a.updateAttachDlg(func(st *attachDlgState) bool {
		if st.account != account || st.kind != kind {
			return false
		}
		if err != nil {
			st.err = err.Error()
			return true
		}
		st.contacts, st.loaded = contacts, true
		return true
	}) {
		return
	}
	a.invalidate()
}

func (a *App) updateAttachDlg(fn func(st *attachDlgState) bool) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.attachDlg == nil {
		return false
	}
	st := *a.attachDlg
	if !fn(&st) {
		return false
	}
	a.attachDlg = &st
	return true
}

func (a *App) closeAttachDialog() {
	a.mu.Lock()
	a.attachDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) sendLocationFromDialog(f frame) {
	if f.selected == nil {
		return
	}
	lat, lon, err := parseCoords(a.wid.attachLatEditor.Text(), a.wid.attachLonEditor.Text())
	if err != nil {
		a.setToast("Invalid " + err.Error())
		return
	}
	accountID, chatID := f.selected.AccountID, f.selected.ChatID
	period := 0
	if a.attachLiveOn && a.attachLiveSel < len(liveDurationChoices) {
		period = liveDurationChoices[a.attachLiveSel].minutes * 60
	}
	a.closeAttachDialog()
	go func() {
		if period > 0 {
			if err := a.eng.SendLiveLocation(accountID, chatID, lat, lon, period); err != nil {
				a.setToast("Send live location failed: " + err.Error())
			}
			return
		}
		if err := a.eng.SendLocation(accountID, chatID, lat, lon); err != nil {
			a.setToast("Send location failed: " + err.Error())
		}
	}()
}

func (a *App) sendContactFromDialog(f frame, c engine.ContactInfo) {
	if f.selected == nil {
		return
	}
	first, last := splitContactName(c.DisplayName)
	accountID, chatID := f.selected.AccountID, f.selected.ChatID
	phone, userID := c.Phone, c.UserID
	a.closeAttachDialog()
	go func() {
		if _, err := a.eng.SendContact(accountID, chatID, phone, first, last, userID); err != nil {
			a.setToast("Share contact failed: " + err.Error())
		}
	}()
}

func (a *App) layoutAttachDialog(gtx layout.Context, f frame) layout.Dimensions {
	st := f.attachDlg

	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, attachDlgKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeAttachDialog()
		}
	}

	if a.wid.attachDlgCloseBtn.Clicked(gtx) {
		a.closeAttachDialog()
	}
	if a.wid.attachDlgSendBtn.Clicked(gtx) {
		a.sendLocationFromDialog(f)
	}
	if a.wid.attachDlgLiveBtn.Clicked(gtx) {
		a.attachLiveOn = !a.attachLiveOn
	}
	if a.attachLiveOn {
		growClickables(&a.wid.liveDurationBtns, len(liveDurationChoices))
		for i := range liveDurationChoices {
			if a.wid.liveDurationBtns[i].Clicked(gtx) {
				a.attachLiveSel = i
			}
		}
	}
	growClickables(&a.wid.attachDlgRowBtns, len(st.contacts))

	title := "Send Location"
	if st.kind == "contact" {
		title = "Share Contact"
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(360))
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(460))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.H3(title)
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if st.kind != "location" {
							return layout.Dimensions{}
						}
						return a.locationDlgBody(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if st.kind != "contact" {
							return layout.Dimensions{}
						}
						return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.contactDlgList(gtx, f, st)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									if st.kind != "location" {
										return layout.Dimensions{}
									}
									label := "Send"
									if a.attachLiveOn {
										label = "Share live"
									}
									bl := material.Button(a.ui.Theme, &a.wid.attachDlgSendBtn, label)
									bl.Background = a.ui.p.Accent
									bl.CornerRadius = 10
									return bl.Layout(gtx)
								}),
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									return layout.Dimensions{}
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									bl := material.Button(a.ui.Theme, &a.wid.attachDlgCloseBtn, "Close")
									bl.Background = a.ui.p.SurfaceHi
									bl.Color = a.ui.p.Text
									bl.CornerRadius = 10
									return bl.Layout(gtx)
								}),
							)
						})
					}),
				)
			})
		})
	})
}

func (a *App) locationDlgBody(gtx layout.Context) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						ed := a.ui.Editor(&a.wid.attachLatEditor, "Latitude (e.g. 41.0082)")
						return ed.Layout(gtx)
					})
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
						return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							ed := a.ui.Editor(&a.wid.attachLonEditor, "Longitude (e.g. 28.9784)")
							return ed.Layout(gtx)
						})
					})
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(12), "Decimal degrees; the recipient sees a map card")
				lbl.Color = a.ui.p.TextFaint
				return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, lbl.Layout)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					btn := material.Button(a.ui.Theme, &a.wid.attachDlgLiveBtn, "Share live location")
					btn.CornerRadius = 10
					btn.TextSize = unit.Sp(13)
					if a.attachLiveOn {
						btn.Background = a.ui.p.Accent
					} else {
						btn.Background = a.ui.p.SurfaceHi
						btn.Color = a.ui.p.Text
					}
					return btn.Layout(gtx)
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if !a.attachLiveOn {
					return layout.Dimensions{}
				}
				return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Spacing: layout.SpaceBetween}.Layout(gtx,
						flexChildrenOf(len(liveDurationChoices), func(gtx layout.Context, i int) layout.Dimensions {
							c := liveDurationChoices[i]
							btn := material.Button(a.ui.Theme, &a.wid.liveDurationBtns[i], c.label)
							btn.CornerRadius = 12
							btn.TextSize = unit.Sp(12)
							btn.Inset = layout.UniformInset(unit.Dp(6))
							if i == a.attachLiveSel {
								btn.Background = a.ui.p.AccentDim
							} else {
								btn.Background = a.ui.p.SurfaceHi
								btn.Color = a.ui.p.Text
							}
							return btn.Layout(gtx)
						})...)
				})
			}),
		)
	})
}

func flexChildrenOf(n int, fn func(gtx layout.Context, i int) layout.Dimensions) []layout.FlexChild {
	children := make([]layout.FlexChild, 0, n)
	for i := 0; i < n; i++ {
		i := i
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return fn(gtx, i)
		}))
	}
	return children
}

func (a *App) contactDlgList(gtx layout.Context, f frame, st *attachDlgState) layout.Dimensions {
	if st.err != "" && !st.loaded {
		return a.centeredStateLabel(gtx, "Failed to load contacts")
	}
	if !st.loaded {
		return a.centeredStateLabel(gtx, "Loading…")
	}
	if len(st.contacts) == 0 {
		return a.centeredStateLabel(gtx, "No contacts")
	}
	a.wid.attachDlgContacts.Axis = layout.Vertical
	lt := material.List(a.ui.Theme, &a.wid.attachDlgContacts)
	return lt.Layout(gtx, len(st.contacts), func(gtx layout.Context, i int) layout.Dimensions {
		c := st.contacts[i]
		if a.wid.attachDlgRowBtns[i].Clicked(gtx) {
			a.sendContactFromDialog(f, c)
		}
		bl := material.ButtonLayout(a.ui.Theme, &a.wid.attachDlgRowBtns[i])
		bl.Background = a.ui.p.SurfaceHi
		bl.CornerRadius = 10
		return layout.Inset{Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return a.streamerB64Avatar(gtx, f, c.DisplayName, c.AvatarB64, unit.Dp(36), dotNone)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										name := c.DisplayName
										if name == "" {
											name = "Contact"
										}
										lbl := a.ui.Label(unit.Sp(14), name)
										if f.cfg.Streamer {
											return a.masked(gtx, lbl.Layout)
										}
										return lbl.Layout(gtx)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										if c.Phone == "" {
											return layout.Dimensions{}
										}
										lbl := a.ui.Dim(unit.Sp(12), c.Phone)
										lbl.Color = a.ui.p.TextFaint
										if f.cfg.Streamer {
											return a.masked(gtx, lbl.Layout)
										}
										return lbl.Layout(gtx)
									}),
								)
							})
						}),
					)
				})
			})
		})
	})
}
