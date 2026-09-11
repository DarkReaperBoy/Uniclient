package gui

import (
	"bytes"
	"encoding/json"
	"fmt"
	"image"
	"strconv"
	"strings"
	"sync"

	_ "image/png" // map-tile web files decode as PNG/JPEG (jpeg registered by media.go)

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

// Location & contact sharing (AyuGram parity, matrix "Attach menu"):
// the attach menu gains Location (a small dialog with lat/lon fields —
// no map picker on desktop builds, honest manual entry per §1.10) and
// Contact (pick one of the account's contacts) wired to engine
// SendLocation / SendContact. Received messages render as dedicated
// bubbles — a map-style card with a pin (tap copies the maps URL, the
// same clipboard-hop as links) and a person card (tap copies the phone).

// ── parse (pure, Extra of content_raw) ─────────────────────────────────────

// geoData is a shared location message's payload.
type geoData struct {
	Lat     float64
	Long    float64
	Live    bool
	Period  int    // seconds (live locations)
	AccHash int64  // geo point access hash — upload.getWebFile tiles need it
	Venue   string // venue title (venue shares)
	Address string // venue address
}

// parseGeoMessage extracts geo coordinates from a cached message's raw
// JSON (cores.Message.Extra["geo_lat"/"geo_long"], written by the
// telegram core's MessageMediaGeo conversion). nil when absent.
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

// mapsURL is the external map link for the point.
func (g *geoData) mapsURL() string {
	if g == nil {
		return ""
	}
	return fmt.Sprintf("https://maps.google.com/?q=%.6f,%.6f", g.Lat, g.Long)
}

// coordLabel is the "lat, long" caption.
func (g *geoData) coordLabel() string {
	if g == nil {
		return ""
	}
	return fmt.Sprintf("%.6f, %.6f", g.Lat, g.Long)
}

// contactData is a shared contact message's payload.
type contactData struct {
	Phone     string
	FirstName string
	LastName  string
	UserID    string
}

// parseContactMessage extracts contact fields from the raw Extra.
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

// fullName joins the contact's name parts.
func (c *contactData) fullName() string {
	if c == nil {
		return ""
	}
	return strings.TrimSpace(c.FirstName + " " + c.LastName)
}

// splitContactName splits a display name into (first, last) for the
// engine's SendContact fields (first token / rest).
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

// parseCoords validates the dialog's editor text into (lat, lon).
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

// ── bubbles ────────────────────────────────────────────────────────────────

// ── map tiles (slice 129) ───────────────────────────────────────────────────
//
// Location cards render a real map tile fetched through the Telegram
// server itself (upload.getWebFile + InputWebFileGeoPointLocation — the
// exact tdesktop mechanism, no third-party tile CDN). Tiles are cached per
// geo point; the pre-fetch state is the honest icon card.

// Tile request shape: the card renders at 220x110dp; request @2x for
// crispness. Zoom 15 shows street-level context around the pin (the engine
// clamps 13..20, 16..1024px).
const (
	mapTileW    = 440
	mapTileH    = 220
	mapTileZoom = 15
)

// mapTileCache holds decoded tiles keyed by geo point (+shape).
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

// mapTileKey identifies one tile request (pure).
func mapTileKey(g *geoData) string {
	if g == nil {
		return ""
	}
	return fmt.Sprintf("map:%.6f,%.6f:%d:%d:%d", g.Lat, g.Long, mapTileW, mapTileH, mapTileZoom)
}

// get returns a cached decoded tile (nil when absent).
func (c *mapTileCache) get(key string) *image.RGBA {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.tiles[key]
}

// claim marks a fetch in-flight; false when one already runs, the tile is
// already cached, or the point previously failed.
func (c *mapTileCache) claim(key string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.busy[key] || c.failed[key] || c.tiles[key] != nil {
		return false
	}
	c.busy[key] = true
	return true
}

// store publishes a decoded tile.
func (c *mapTileCache) store(key string, img *image.RGBA) {
	c.mu.Lock()
	c.tiles[key], c.busy[key] = img, false
	c.mu.Unlock()
}

// fail pins the honest fallback for this point (no retry churn).
func (c *mapTileCache) fail(key string) {
	c.mu.Lock()
	c.busy[key], c.failed[key] = false, true
	c.mu.Unlock()
}

// ensureMapTile kicks the async tile fetch for a location message.
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
		img, _, derr := image.Decode(bytes.NewReader(data))
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

// imageToRGBA converts any decoded image into RGBA for the paint path.
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

// drawTileCover paints a tile cover-fitted into w×h with rounded corners
// (the rect-shaped sibling of avatar.go's square drawImageRRectCover).
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

// locationBubble: map card — the fetched tile (cover-fitted, Telegram's own
// upload.getWebFile geo tiles) with a centered pin and a caption pill; the
// honest icon card before the tile lands (or on platforms without tile
// support). Venue shares caption with their real title + address.
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
	return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
		return layout.Stack{}.Layout(gtx,
			layout.Expanded(func(gtx layout.Context) layout.Dimensions {
				if tile != nil {
					return drawTileCover(gtx, tile, w, h)
				}
				return layout.Dimensions{}
			}),
			layout.Stacked(func(gtx layout.Context) layout.Dimensions {
				if tile != nil {
					// Tile state: centered pin over the map.
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
				// Pre-fetch state: the full honest icon card.
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
				// Caption pill pinned to the card's bottom-left.
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

// overlayBadge paints a small accent chip at the card's top-right.
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

// liveBadgeText is the live-location chip label ("" when not live).
func liveBadgeText(g *geoData) string {
	if g == nil || !g.Live {
		return ""
	}
	if g.Period > 0 {
		return "live · " + itoa(g.Period/60) + "m"
	}
	return "live"
}

// contactBubble: person card — avatar circle, name, phone.
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

// ── attach dialog (send location / share contact) ──────────────────────────

// attachDlgState is the open attach helper dialog.
type attachDlgState struct {
	kind    string // "location" | "contact"
	account string
	// contact mode:
	contacts []engine.ContactInfo
	loaded   bool
	err      string
}

var (
	attachDlgCloseBtn widget.Clickable
	attachDlgSendBtn  widget.Clickable
	attachDlgRowBtns  []widget.Clickable
	attachLatEditor   widget.Editor
	attachLonEditor   widget.Editor
	attachDlgKeyTag   = new(struct{})
	attachDlgContacts widget.List
)

func init() {
	attachLatEditor.SingleLine = true
	attachLonEditor.SingleLine = true
}

// openAttachDialog opens the location/contact helper (needs an open chat).
func (a *App) openAttachDialog(kind string) {
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
		account, st2 := account, st
		go func() {
			contacts, err := a.eng.GetContacts(account)
			a.mu.Lock()
			if a.attachDlg != st2 {
				a.mu.Unlock()
				return
			}
			if err != nil {
				st2.err = err.Error()
			} else {
				st2.contacts, st2.loaded = contacts, true
			}
			a.mu.Unlock()
			a.invalidate()
		}()
	}
}

// closeAttachDialog dismisses it.
func (a *App) closeAttachDialog() {
	a.mu.Lock()
	a.attachDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// sendLocationFromDialog validates the editors and sends (async).
func (a *App) sendLocationFromDialog(f frame) {
	if f.selected == nil {
		return
	}
	lat, lon, err := parseCoords(attachLatEditor.Text(), attachLonEditor.Text())
	if err != nil {
		a.setToast("Invalid " + err.Error())
		return
	}
	accountID, chatID := f.selected.AccountID, f.selected.ChatID
	a.closeAttachDialog()
	go func() {
		if err := a.eng.SendLocation(accountID, chatID, lat, lon); err != nil {
			a.setToast("Send location failed: " + err.Error())
		}
	}()
}

// sendContactFromDialog shares one contact into the open chat (async).
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

// layoutAttachDialog renders the location/contact helper (content-pane
// replacement, like the other composer dialogs).
func (a *App) layoutAttachDialog(gtx layout.Context, f frame) layout.Dimensions {
	st := f.attachDlg

	// Esc closes (self-handled).
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

	if attachDlgCloseBtn.Clicked(gtx) {
		a.closeAttachDialog()
	}
	if attachDlgSendBtn.Clicked(gtx) {
		a.sendLocationFromDialog(f)
	}
	growClickables(&attachDlgRowBtns, len(st.contacts))

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
					// action row
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									if st.kind != "location" {
										return layout.Dimensions{}
									}
									bl := material.Button(a.ui.Theme, &attachDlgSendBtn, "Send")
									bl.Background = a.ui.p.Accent
									bl.CornerRadius = 10
									return bl.Layout(gtx)
								}),
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									return layout.Dimensions{}
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									bl := material.Button(a.ui.Theme, &attachDlgCloseBtn, "Close")
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

// locationDlgBody: latitude/longitude fields + hint.
func (a *App) locationDlgBody(gtx layout.Context) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						ed := a.ui.Editor(&attachLatEditor, "Latitude (e.g. 41.0082)")
						return ed.Layout(gtx)
					})
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
						return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							ed := a.ui.Editor(&attachLonEditor, "Longitude (e.g. 28.9784)")
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
		)
	})
}

// contactDlgList: the account's contacts; tap one to share.
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
	attachDlgContacts.Axis = layout.Vertical
	lt := material.List(a.ui.Theme, &attachDlgContacts)
	return lt.Layout(gtx, len(st.contacts), func(gtx layout.Context, i int) layout.Dimensions {
		c := st.contacts[i]
		if attachDlgRowBtns[i].Clicked(gtx) {
			a.sendContactFromDialog(f, c)
		}
		bl := material.ButtonLayout(a.ui.Theme, &attachDlgRowBtns[i])
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
