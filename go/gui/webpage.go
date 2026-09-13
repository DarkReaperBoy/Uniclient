package gui

import (
	"bytes"
	"encoding/json"
	"image"
	"strings"
	"sync"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"

	"uniclient/engine"
)

// Webpage/link previews (slice 117, Telegram parity rows "Webpage preview
// toggle" + "Webpage/link preview card"): messages carrying a link preview
// render the site card (thumb + site + title + description) above the text,
// and the a.wid.composer gains the preview on/off toggle (link icon, visible only
// while the text contains a link — §1.10 honest gating). The core already
// caches wp_* fields in the message Extra (content_raw); sending without a
// preview rides the new no_webpage flag (engine → SetNoWebpage).

// webPageData is the parsed link preview of one message.
type webPageData struct {
	URL         string
	SiteName    string
	Title       string
	Description string
	Type        string
	ThumbB64    string
	Width       int
	Height      int
	Duration    int
	PhotoID     string // slice 130: the page photo's download coords
	PhotoExtra  string
	HasIV       bool // slice 176: the page has an Instant View version
}

// hasPhotoID reports whether the card can ensure a full-res photo thumb.
func (w *webPageData) hasPhotoID() bool {
	return w != nil && w.PhotoID != "" && w.PhotoExtra != ""
}

// parseWebPage extracts the preview from a cached message's raw Extra
// (cores.Message.Extra["wp_*"], written by the telegram core's
// MessageMediaWebPage conversion). Nil when the message has none.
// Pure — unit-tested.
func parseWebPage(m *engine.CachedMessage) *webPageData {
	if m == nil || len(m.ContentRaw) == 0 {
		return nil
	}
	if !bytes.Contains(m.ContentRaw, []byte(`"wp_url"`)) {
		return nil
	}
	var env struct {
		Extra map[string]interface{} `json:"extra"`
	}
	if err := json.Unmarshal(m.ContentRaw, &env); err != nil || env.Extra == nil {
		return nil
	}
	url, _ := env.Extra["wp_url"].(string)
	if url == "" {
		return nil
	}
	wp := &webPageData{URL: url}
	wp.SiteName, _ = env.Extra["wp_site_name"].(string)
	wp.Title, _ = env.Extra["wp_title"].(string)
	wp.Description, _ = env.Extra["wp_description"].(string)
	wp.Type, _ = env.Extra["wp_type"].(string)
	wp.ThumbB64, _ = env.Extra["wp_thumb_b64"].(string)
	wp.PhotoID, _ = env.Extra["wp_photo_id"].(string)
	wp.PhotoExtra, _ = env.Extra["wp_photo_extra"].(string)
	wp.HasIV, _ = env.Extra["wp_has_iv"].(bool)
	if v, ok := env.Extra["wp_photo_w"].(float64); ok {
		wp.Width = int(v)
	}
	if v, ok := env.Extra["wp_photo_h"].(float64); ok {
		wp.Height = int(v)
	}
	if v, ok := env.Extra["wp_duration"].(float64); ok {
		wp.Duration = int(v)
	}
	return wp
}

// hostname returns the URL's host for display (raw string when malformed).
func (w *webPageData) hostname() string {
	s := w.URL
	for _, prefix := range []string{"https://", "http://"} {
		if strings.HasPrefix(s, prefix) {
			s = s[len(prefix):]
			break
		}
	}
	if i := strings.IndexByte(s, '/'); i >= 0 {
		s = s[:i]
	}
	return s
}

// displayTitle: the page title, else the site name, else the host.
func (w *webPageData) displayTitle() string {
	if w.Title != "" {
		return w.Title
	}
	if w.SiteName != "" {
		return w.SiteName
	}
	return w.hostname()
}

// composedHasLink reports whether the a.wid.composer text carries an http(s)/www
// link — the gate for the preview toggle. Pure — unit-tested.
func composedHasLink(text string) bool {
	for _, prefix := range []string{"https://", "http://", "www."} {
		if strings.Contains(text, prefix) {
			return true
		}
	}
	return false
}

// linkPreviewOff tracks the a.wid.composer's preview toggle per chat (Telegram
// remembers per chat; resets are per session). Keyed by chatKey.String().
var (
	linkPreviewMu sync.Mutex
	linkPreview   = map[string]bool{}
)

// linkPreviewOffFor reports the toggle for the chat being sent to.
func (a *App) linkPreviewOffFor(k *chatKey) bool {
	if k == nil {
		return false
	}
	linkPreviewMu.Lock()
	defer linkPreviewMu.Unlock()
	return linkPreview[k.String()]
}

// a.wid.webPageClickables pools the card clickables per message.

func (a *App) webPageClickable(key string) *widget.Clickable {
	if c, ok := a.wid.webPageClickables[key]; ok {
		return c
	}
	if len(a.wid.webPageClickables) > 512 {
		a.wid.webPageClickables = make(map[string]*widget.Clickable)
	}
	c := new(widget.Clickable)
	a.wid.webPageClickables[key] = c
	return c
}

// webPhotoEnsured guards one EnsureWebPagePhoto call per message (the
// engine method is idempotent, but it hits the DB — the GUI must not call
// it every frame). Failures pin permanently: no retry churn.
var (
	webPhotoMu     sync.Mutex
	webPhotoDone   = map[string]bool{}
	webPhotoFailed = map[string]bool{}
)

// ensureWebPagePhoto resolves the card's full-res photo into the download
// pipeline (dice-style media-row rewrite, engine slice 130).
func (a *App) ensureWebPagePhoto(m *engine.CachedMessage, wp *webPageData) {
	if m == nil || wp == nil || !wp.hasPhotoID() {
		return
	}
	// Already downloaded? Nothing to ensure.
	if m.HasMedia && m.MediaDownloadState == engine.DownloadComplete && m.MediaLocalPath != "" {
		return
	}
	key := m.AccountID + "|" + m.ChatID + "|" + m.MsgID
	webPhotoMu.Lock()
	if webPhotoDone[key] || webPhotoFailed[key] {
		webPhotoMu.Unlock()
		return
	}
	webPhotoDone[key] = true
	webPhotoMu.Unlock()
	go func() {
		if err := a.eng.EnsureWebPagePhoto(m.AccountID, m.ChatID, m.MsgID); err != nil {
			webPhotoMu.Lock()
			webPhotoFailed[key] = true
			webPhotoMu.Unlock()
		}
	}()
}

// webPageThumbWidget renders the card thumbnail: the downloaded full-res
// photo when complete, the inline stripped thumb until then, nothing when
// the page has neither (honest).
func (a *App) webPageThumbWidget(gtx layout.Context, m *engine.CachedMessage, wp *webPageData) layout.Dimensions {
	if m == nil || wp == nil {
		return layout.Dimensions{}
	}
	if m.HasMedia && m.MediaDownloadState == engine.DownloadComplete &&
		m.MediaLocalPath != "" && isDisplayableImage(m.MediaLocalPath) {
		key := "file:" + m.MediaLocalPath
		if img := mediaImgs.get(key); img != nil {
			return drawImageRRectCover(gtx, img, gtx.Dp(unit.Dp(52)))
		}
		a.decodeFileAsync(m.MediaLocalPath)
		// Stripped thumb while the decode runs.
		if wp.ThumbB64 != "" {
			return a.mediaThumb(gtx, wp.ThumbB64, unit.Dp(52))
		}
		return layout.Dimensions{}
	}
	if wp.ThumbB64 != "" {
		return a.mediaThumb(gtx, wp.ThumbB64, unit.Dp(52))
	}
	return layout.Dimensions{}
}

// webPageBlock renders the link-preview card above the message text:
// thumbnail (when cached), site name (small, dim), title (semi-bold),
// description (2 lines), optional duration pill. Tap opens the URL in the
// system browser (the openext pipeline).
func (a *App) webPageBlock(gtx layout.Context, m *engine.CachedMessage) layout.Dimensions {
	wp := parseWebPage(m)
	if wp == nil {
		return layout.Dimensions{}
	}
	key := m.AccountID + "|" + m.ChatID + "|" + m.MsgID
	a.ensureWebPagePhoto(m, wp)
	btn := a.webPageClickable(key)
	if btn.Clicked(gtx) {
		// Slice 176: pages with an Instant View version open the in-app
		// reader; everything else stays on the browser pipeline.
		if wp.HasIV {
			a.openInstantView(m.AccountID, wp.URL)
		} else {
			openExternalAsync(wp.URL, func(err error) {
				if err != nil {
					a.setToast("Open link failed: " + err.Error())
				}
			})
		}
	}
	return layout.Inset{Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			// Card frame: rounded surface-tinted panel.
			return roundedFill(gtx, a.ui.p.SurfaceHi, unit.Dp(8), func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					row := []layout.FlexChild{}
					if thumb := a.webPageThumbWidget(gtx, m, wp); thumb.Size != (image.Point{}) {
						row = append(row, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return a.webPageThumbWidget(gtx, m, wp)
							})
						}))
					}
					meta := []layout.FlexChild{
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(11), strings.ToUpper(wp.SiteName))
							lbl.Color = a.ui.p.TextDim
							lbl.MaxLines = 1
							return lbl.Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Top: unit.Dp(1)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(13), wp.displayTitle())
								lbl.MaxLines = 2
								return lbl.Layout(gtx)
							})
						}),
					}
					if wp.Description != "" {
						meta = append(meta, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(12), wp.Description)
								lbl.MaxLines = 2
								return lbl.Layout(gtx)
							})
						}))
					}
					row = append(row, layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx, meta...)
					}))
					if wp.Duration > 0 {
						row = append(row, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(10), fmtDur(wp.Duration))
								return lbl.Layout(gtx)
							})
						}))
					}
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx, row...)
				})
			})
		})
	})
}
