package gui

import (
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"gioui.org/font"
	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/cores"
	"uniclient/engine"
)

// Instant View reader (slice 176, parity row "Instant View pages" —
// tdesktop's IV panel): messages whose link preview carries an IV page
// (wp_has_iv) open the article in an in-app reader overlay instead of the
// browser; telegra.ph / graph.org text links do the same (the core's
// isKnownIVDomain gate mirrored GUI-side). Related articles navigate
// inside the reader with a back stack. The reader renders every IV block
// the telegram core emits (ivBlockToMap's shapes); video/audio blocks
// download via the engine's IV document downloader and hand off to the
// system player (the slice-86 pattern — no in-app video decode, §1.10).

// ivHistMax caps the related-article back stack.
const ivHistMax = 16

// ivPage is one parsed Instant View page.
type ivPage struct {
	URL      string
	Title    string
	SiteName string
	RTL      bool
	V2       bool
	Blocks   []ivBlock
}

// ivBlock is one rendered block (the core's JSON map per block).
type ivBlock struct {
	Type string

	Text    ivRich // title/subtitle/header/subheader/paragraph/preformatted/footer/kicker + quote/pull text + details/related/table titles
	Caption ivRich // quote/pull/photo/video/audio/embed captions
	Lang    string // preformatted
	Name    string // anchor
	Date    int64  // author_date / embed_post
	Author  ivRich // author_date author

	URL  string // photo permalink / embed url / embed_post url
	HTML string // embed html
	W, H int    // photo/video/embed dims

	PhotoID  int64
	VideoID  int64
	AudioID  int64
	ThumbB64 string
	Extra    string
	Mime     string
	Size     int64
	Duration int
	Filename string
	Autoplay bool
	Loop     bool

	Open     bool // details default-open
	Bordered bool // table
	Striped  bool // table

	ChannelTitle string
	Username     string
	ChannelID    int64

	AuthorName string // embed_post
	Items      []ivBlock

	ListItems []ivListItem
	Articles  []ivArticle
	Rows      [][]ivTableCell
}

// ivListItem is one list / ordered-list entry (text or nested blocks).
type ivListItem struct {
	Num       int
	Text      ivRich
	Blocks    []ivBlock
	HasBlocks bool
}

// ivArticle is one related-article row.
type ivArticle struct {
	URL    string
	Title  string
	Desc   string
	Author string
}

// ivTableCell is one table cell.
type ivTableCell struct {
	Text                       ivRich
	Header                     bool
	Colspan, Rowspan           int
	AlignCenter, AlignRight    bool
	ValignMiddle, ValignBottom bool
}

// ivRich is the IV rich-text tree (tg.RichTextClass mapped by the core).
type ivRich struct {
	Kind     string // plain/bold/italic/underline/strike/fixed/url/email/concat
	Text     string
	Href     string
	Email    string
	Children []ivRich
}

// ivSpan is one flattened styled run of the rich-text tree.
type ivSpan struct {
	Text              string
	Bold, Italic      bool
	Underline, Strike bool
	Fixed             bool
	Href, Email       string
}

// ivRichSpans flattens the rich-text tree into styled spans, propagating
// the enclosing styles down. Pure — unit-tested.
func ivRichSpans(root ivRich) []ivSpan {
	var out []ivSpan
	var walk func(n ivRich, st ivSpan)
	walk = func(n ivRich, st ivSpan) {
		switch n.Kind {
		case "plain":
			if n.Text != "" {
				s := st
				s.Text = n.Text
				out = append(out, s)
			}
			return
		case "bold":
			st.Bold = true
		case "italic":
			st.Italic = true
		case "underline":
			st.Underline = true
		case "strike":
			st.Strike = true
		case "fixed":
			st.Fixed = true
		case "url":
			st.Href = n.Href
		case "email":
			st.Email = n.Email
		}
		for _, c := range n.Children {
			walk(c, st)
		}
	}
	walk(root, ivSpan{})
	return out
}

// ivSpanEntities renders spans as plain text + Telegram-style entities so
// the existing flowRich renderer (wrapping, link taps, mono pills) can
// paint them. Offsets are UTF-16 code units (parseRichSegments contract).
func ivSpanEntities(spans []ivSpan) (string, []cores.TextEntity) {
	var sb strings.Builder
	var ents []cores.TextEntity
	u16 := 0
	for _, s := range spans {
		start := u16
		sb.WriteString(s.Text)
		u16 += utf16Len(s.Text)
		if s.Bold {
			ents = append(ents, cores.TextEntity{Type: "bold", Offset: start, Length: u16 - start})
		}
		if s.Italic {
			ents = append(ents, cores.TextEntity{Type: "italic", Offset: start, Length: u16 - start})
		}
		if s.Underline {
			ents = append(ents, cores.TextEntity{Type: "underline", Offset: start, Length: u16 - start})
		}
		if s.Strike {
			ents = append(ents, cores.TextEntity{Type: "strike", Offset: start, Length: u16 - start})
		}
		if s.Fixed {
			ents = append(ents, cores.TextEntity{Type: "code", Offset: start, Length: u16 - start})
		}
		if s.Href != "" {
			ents = append(ents, cores.TextEntity{Type: "text_url", Offset: start, Length: u16 - start, URL: s.Href})
		}
		if s.Email != "" {
			ents = append(ents, cores.TextEntity{Type: "email", Offset: start, Length: u16 - start})
		}
	}
	return sb.String(), ents
}

// ivKnownHost mirrors the core's isKnownIVDomain gate: telegra.ph and
// graph.org hosts (subdomains included) always have an IV page. Pure.
func ivKnownHost(rawURL string) bool {
	u, err := url.Parse(rawURL)
	if err != nil {
		return false
	}
	host := strings.ToLower(u.Hostname())
	for _, d := range []string{"telegra.ph", "graph.org"} {
		if host == d || strings.HasSuffix(host, "."+d) {
			return true
		}
	}
	return false
}

// ivRichFromMap converts the core's rich-text JSON (map form) into the
// ivRich tree. Unknown kinds keep their children (honest passthrough).
func ivRichFromMap(v interface{}) ivRich {
	var rt ivRich
	m, ok := v.(map[string]interface{})
	if !ok {
		return rt
	}
	rt.Kind, _ = m["t"].(string)
	switch rt.Kind {
	case "plain":
		rt.Text, _ = m["v"].(string)
	case "url":
		rt.Href, _ = m["href"].(string)
	case "email":
		rt.Email, _ = m["addr"].(string)
	}
	if cs, ok := m["c"].([]interface{}); ok {
		for _, c := range cs {
			rt.Children = append(rt.Children, ivRichFromMap(c))
		}
	} else if c, ok := m["c"].(map[string]interface{}); ok {
		rt.Children = append(rt.Children, ivRichFromMap(c))
	}
	return rt
}

func ivFloat(m map[string]interface{}, k string) int {
	if f, ok := m[k].(float64); ok {
		return int(f)
	}
	return 0
}

func ivInt64(m map[string]interface{}, k string) int64 {
	if f, ok := m[k].(float64); ok {
		return int64(f)
	}
	return 0
}

func ivStr(m map[string]interface{}, k string) string {
	s, _ := m[k].(string)
	return s
}

func ivBool(m map[string]interface{}, k string) bool {
	b, _ := m[k].(bool)
	return b
}

// ivBlocksFromAny converts raw JSON block maps into ivBlock values.
func ivBlocksFromAny(raw interface{}) []ivBlock {
	arr, ok := raw.([]interface{})
	if !ok {
		return nil
	}
	var out []ivBlock
	for _, it := range arr {
		m, ok := it.(map[string]interface{})
		if !ok {
			continue
		}
		b := ivBlock{Type: ivStr(m, "type")}
		switch b.Type {
		case "title", "subtitle", "header", "subheader", "paragraph", "preformatted", "footer", "kicker":
			b.Text = ivRichFromMap(m["text"])
			b.Lang = ivStr(m, "lang")
		case "author_date":
			b.Author = ivRichFromMap(m["author"])
			b.Date = int64(ivFloat(m, "date"))
		case "anchor":
			b.Name = ivStr(m, "name")
		case "blockquote", "pullquote":
			b.Text = ivRichFromMap(m["text"])
			b.Caption = ivRichFromMap(m["caption"])
		case "photo":
			b.PhotoID = ivInt64(m, "photo_id")
			b.ThumbB64 = ivStr(m, "thumb")
			b.Extra = ivStr(m, "extra")
			b.W, b.H = ivFloat(m, "w"), ivFloat(m, "h")
			b.Caption = ivRichFromMap(m["caption"])
			b.URL = ivStr(m, "url")
		case "video":
			b.VideoID = ivInt64(m, "video_id")
			b.ThumbB64 = ivStr(m, "thumb")
			b.Extra = ivStr(m, "extra")
			b.Mime = ivStr(m, "mime")
			b.Size = ivInt64(m, "size")
			b.Duration = ivFloat(m, "duration")
			b.W, b.H = ivFloat(m, "w"), ivFloat(m, "h")
			b.Filename = ivStr(m, "filename")
			b.Autoplay = ivBool(m, "autoplay")
			b.Loop = ivBool(m, "loop")
			b.Caption = ivRichFromMap(m["caption"])
		case "audio":
			b.AudioID = ivInt64(m, "audio_id")
			b.Extra = ivStr(m, "extra")
			b.Mime = ivStr(m, "mime")
			b.Size = ivInt64(m, "size")
			b.Duration = ivFloat(m, "duration")
			b.Filename = ivStr(m, "filename")
			b.Caption = ivRichFromMap(m["caption"])
		case "cover":
			if inner := ivBlocksFromAny([]interface{}{m["cover"]}); len(inner) > 0 {
				b.Items = inner
			}
		case "embed":
			b.URL = ivStr(m, "url")
			b.HTML = ivStr(m, "html")
			b.W, b.H = ivFloat(m, "w"), ivFloat(m, "h")
			b.Caption = ivRichFromMap(m["caption"])
		case "embed_post":
			b.URL = ivStr(m, "url")
			b.AuthorName = ivStr(m, "author")
			b.Date = int64(ivFloat(m, "date"))
			b.Caption = ivRichFromMap(m["caption"])
			b.Items = ivBlocksFromAny(m["blocks"])
		case "collage", "slideshow":
			b.Items = ivBlocksFromAny(m["items"])
			b.Caption = ivRichFromMap(m["caption"])
		case "details":
			b.Text = ivRichFromMap(m["title"])
			b.Items = ivBlocksFromAny(m["blocks"])
			b.Open = ivBool(m, "open")
		case "related":
			b.Text = ivRichFromMap(m["title"])
			if arr, ok := m["articles"].([]interface{}); ok {
				for _, a := range arr {
					am, ok := a.(map[string]interface{})
					if !ok {
						continue
					}
					b.Articles = append(b.Articles, ivArticle{
						URL:    ivStr(am, "url"),
						Title:  ivStr(am, "title"),
						Desc:   ivStr(am, "desc"),
						Author: ivStr(am, "author"),
					})
				}
			}
		case "table":
			b.Text = ivRichFromMap(m["title"])
			b.Bordered = ivBool(m, "bordered")
			b.Striped = ivBool(m, "striped")
			if rows, ok := m["rows"].([]interface{}); ok {
				for _, r := range rows {
					cellsRaw, ok := r.([]interface{})
					if !ok {
						continue
					}
					var cells []ivTableCell
					for _, c := range cellsRaw {
						cm, ok := c.(map[string]interface{})
						if !ok {
							continue
						}
						cells = append(cells, ivTableCell{
							Text:         ivRichFromMap(cm["text"]),
							Header:       ivBool(cm, "header"),
							Colspan:      ivFloat(cm, "colspan"),
							Rowspan:      ivFloat(cm, "rowspan"),
							AlignCenter:  ivBool(cm, "align_center"),
							AlignRight:   ivBool(cm, "align_right"),
							ValignMiddle: ivBool(cm, "valign_middle"),
							ValignBottom: ivBool(cm, "valign_bottom"),
						})
					}
					b.Rows = append(b.Rows, cells)
				}
			}
		case "channel":
			b.ChannelTitle = ivStr(m, "title")
			b.Username = ivStr(m, "username")
			b.ChannelID = ivInt64(m, "id")
		case "list", "ordered_list":
			if items, ok := m["items"].([]interface{}); ok {
				for _, it := range items {
					im, ok := it.(map[string]interface{})
					if !ok {
						continue
					}
					li := ivListItem{Num: ivFloat(im, "num")}
					if _, hasText := im["text"]; hasText {
						li.Text = ivRichFromMap(im["text"])
					} else if bl, hasBlocks := im["blocks"].([]interface{}); hasBlocks {
						li.Blocks = ivBlocksFromAny(bl)
						li.HasBlocks = true
					}
					b.ListItems = append(b.ListItems, li)
				}
			}
		}
		out = append(out, b)
	}
	return out
}

// parseIVPage decodes the core's GetInstantViewPage JSON. Nil when the
// payload is not a usable page (empty / garbage). Pure — unit-tested.
func parseIVPage(data []byte) *ivPage {
	var env struct {
		URL      string        `json:"url"`
		Title    string        `json:"title"`
		SiteName string        `json:"site_name"`
		RTL      bool          `json:"rtl"`
		V2       bool          `json:"v2"`
		Blocks   []interface{} `json:"blocks"`
	}
	if err := json.Unmarshal(data, &env); err != nil {
		return nil
	}
	if env.URL == "" || len(env.Blocks) == 0 {
		return nil
	}
	p := &ivPage{
		URL:      env.URL,
		Title:    env.Title,
		SiteName: env.SiteName,
		RTL:      env.RTL,
		V2:       env.V2,
		Blocks:   ivBlocksFromAny(env.Blocks),
	}
	if len(p.Blocks) == 0 {
		return nil
	}
	return p
}

// ivState is the reader overlay's live state (App-owned, mirrored to the
// frame like the media viewer).
type ivState struct {
	accountID string
	url       string
	loading   bool
	err       string
	page      *ivPage
	hist      []*ivPage // back stack for related-article navigation

	detailsOpen map[string]bool // block idx → override
	slideIdx    map[string]int  // slideshow block idx → item index
	docBusy     map[string]bool // video/audio doc key → download in flight
}

// pushHistory replaces the shown page, pushing the current one onto the
// back stack (capped at ivHistMax).
func (s *ivState) pushHistory(next *ivPage) {
	if s.page != nil {
		s.hist = append(s.hist, s.page)
		if len(s.hist) > ivHistMax {
			s.hist = s.hist[len(s.hist)-ivHistMax:]
		}
	}
	s.page = next
	if s.page != nil {
		s.url = s.page.URL
		s.loading = false
		s.err = ""
	}
}

// back pops the history; false when already at the root (the overlay
// closes then).
func (s *ivState) back() bool {
	if len(s.hist) == 0 {
		return false
	}
	s.page = s.hist[len(s.hist)-1]
	s.hist = s.hist[:len(s.hist)-1]
	s.url = s.page.URL
	s.loading = false
	s.err = ""
	return true
}

// detailsOpenAt resolves a details block's open state (override wins).
func (s *ivState) detailsOpenAt(idx int, def bool) bool {
	if s.detailsOpen == nil {
		return def
	}
	if v, ok := s.detailsOpen[strconv.Itoa(idx)]; ok {
		return v
	}
	return def
}

// setDetailsOpen records an override.
func (s *ivState) setDetailsOpen(idx int, v bool) {
	if s.detailsOpen == nil {
		s.detailsOpen = map[string]bool{}
	}
	s.detailsOpen[strconv.Itoa(idx)] = v
}

// slideAt returns the slideshow item index for a block idx.
func (s *ivState) slideAt(path string) int {
	if s.slideIdx == nil {
		return 0
	}
	return s.slideIdx[path]
}

// setSlideAt records the slideshow item index.
func (s *ivState) setSlideAt(path string, i int) {
	if s.slideIdx == nil {
		s.slideIdx = map[string]int{}
	}
	s.slideIdx[path] = i
}

// openInstantView opens the reader on url (async fetch). On fetch error
// it toasts and falls back to the browser — never a dead overlay (§1.10).
func (a *App) openInstantView(accountID, pageURL string) {
	if accountID == "" || pageURL == "" {
		return
	}
	a.mu.Lock()
	a.iv = &ivState{accountID: accountID, url: pageURL, loading: true}
	a.mu.Unlock()
	a.invalidate()
	go func() {
		data, err := a.eng.GetInstantViewPage(accountID, pageURL)
		a.mu.Lock()
		cur := a.iv
		if cur == nil || cur.accountID != accountID || cur.url != pageURL {
			a.mu.Unlock()
			return // user moved on
		}
		if err != nil {
			cur.loading = false
			cur.err = err.Error()
			a.mu.Unlock()
			a.invalidate()
			a.setToast("Instant View unavailable: " + err.Error())
			return
		}
		p := parseIVPage(data)
		if p == nil {
			cur.loading = false
			cur.err = "no instant view for this page"
			a.mu.Unlock()
			a.invalidate()
			openExternalAsync(pageURL, func(e error) {
				if e != nil {
					a.setToast("Open link failed: " + e.Error())
				}
			})
			return
		}
		cur.page = p
		cur.loading = false
		cur.err = ""
		a.mu.Unlock()
		a.invalidate()
	}()
}

// ivOpenRelated navigates inside the reader (related-article row):
// fetches the next page, pushing history.
func (a *App) ivOpenRelated(accountID, pageURL string) {
	if accountID == "" || pageURL == "" {
		return
	}
	a.mu.Lock()
	cur := a.iv
	if cur == nil || cur.accountID != accountID {
		a.mu.Unlock()
		return
	}
	cur.loading = true
	cur.err = ""
	a.mu.Unlock()
	a.invalidate()
	go func() {
		data, err := a.eng.GetInstantViewPage(accountID, pageURL)
		a.mu.Lock()
		cur := a.iv
		if cur == nil || cur.accountID != accountID || !cur.loading {
			a.mu.Unlock()
			return
		}
		if err != nil {
			cur.loading = false
			cur.err = err.Error()
			a.mu.Unlock()
			a.invalidate()
			a.setToast("Instant View unavailable: " + err.Error())
			return
		}
		p := parseIVPage(data)
		if p == nil {
			cur.loading = false
			cur.err = "no instant view for this page"
			a.mu.Unlock()
			a.invalidate()
			openExternalAsync(pageURL, func(e error) {
				if e != nil {
					a.setToast("Open link failed: " + e.Error())
				}
			})
			return
		}
		cur.pushHistory(p)
		a.mu.Unlock()
		a.invalidate()
	}()
}

// closeInstantView dismisses the reader.
func (a *App) closeInstantView() {
	a.mu.Lock()
	a.iv = nil
	a.mu.Unlock()
	a.invalidate()
}

// ivBack: history pop, or close at the root.
func (a *App) ivBack() {
	a.mu.Lock()
	st := a.iv
	if st == nil {
		a.mu.Unlock()
		return
	}
	if !st.back() {
		a.iv = nil
		a.mu.Unlock()
		a.invalidate()
		return
	}
	a.mu.Unlock()
	a.invalidate()
}

// layoutInstantView: full-window reader overlay (above the media viewer,
// below the call overlay). Full surface like tdesktop's panel.
func (a *App) layoutInstantView(gtx layout.Context, f frame) layout.Dimensions {
	st := f.iv
	gtx.Execute(key.FocusCmd{Tag: nil})

	// Esc: back/close.
	{
		stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
		event.Op(gtx.Ops, ivKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.ivBack()
		}
	}

	paintFill(gtx.Ops, a.ui.p.Background, gtx.Constraints.Max)

	header := layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.ivTopBar(gtx, f, st)
	})
	body := layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
		switch {
		case st.loading:
			return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return a.ui.Dim(unit.Sp(14), "Loading page…").Layout(gtx)
			})
		case st.page == nil:
			return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				if st.err != "" {
					return a.ui.Dim(unit.Sp(13), "Instant View unavailable").Layout(gtx)
				}
				return layout.Dimensions{}
			})
		default:
			return a.ivBody(gtx, f, st)
		}
	})

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, header, body)
}

// ivTopBar: back chevron, site + title, open-in-browser action.
func (a *App) ivTopBar(gtx layout.Context, f frame, st *ivState) layout.Dimensions {
	back := &a.wid.ivBackBtn
	if back.Clicked(gtx) {
		a.ivBack()
	}
	title := st.page.Title
	if title == "" {
		title = st.url
	}
	return layout.Inset{Left: unit.Dp(4), Right: unit.Dp(8), Top: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.ui.IconButton(back, iconNavigationBack, "Back").Layout(gtx)
			}),
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Left: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							site := st.page.SiteName
							if site == "" {
								site = ivHostOf(st.url)
							}
							lbl := a.ui.Label(unit.Sp(11), strings.ToUpper(site))
							lbl.Color = a.ui.p.TextDim
							lbl.MaxLines = 1
							return lbl.Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(14), title)
							lbl.MaxLines = 1
							return lbl.Layout(gtx)
						}),
					)
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := &a.wid.ivOpenBtn
				if btn.Clicked(gtx) {
					openExternalAsync(st.url, func(err error) {
						if err != nil {
							a.setToast("Open link failed: " + err.Error())
						}
					})
				}
				return a.ui.IconButton(btn, iconContentLink, "Open in browser").Layout(gtx)
			}),
		)
	})
}

// ivBody: the scrollable block column (centered, capped width).
func (a *App) ivBody(gtx layout.Context, f frame, st *ivState) layout.Dimensions {
	maxW := gtx.Dp(unit.Dp(720))
	inner := gtx.Constraints.Max.X
	if inner > maxW {
		inner = maxW
	}
	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = inner
		return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(24), Left: unit.Dp(16), Right: unit.Dp(16)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return material.List(a.ui.Theme, &a.wid.ivList).Layout(gtx, len(st.page.Blocks), func(gtx layout.Context, idx int) layout.Dimensions {
				return layout.Inset{Bottom: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return a.ivBlockWidget(gtx, f, st, &st.page.Blocks[idx], idx)
				})
			})
		})
	})
}

// ivBlockWidget dispatches one block renderer.
func (a *App) ivBlockWidget(gtx layout.Context, f frame, st *ivState, b *ivBlock, idx int) layout.Dimensions {
	switch b.Type {
	case "title":
		return a.ivRichBlock(gtx, f, st, b, idx, unit.Sp(24), true, a.ui.p.Text)
	case "subtitle":
		return a.ivRichBlock(gtx, f, st, b, idx, unit.Sp(17), false, a.ui.p.TextDim)
	case "kicker":
		return a.ivRichBlock(gtx, f, st, b, idx, unit.Sp(11), false, a.ui.p.Accent)
	case "header":
		return a.ivRichBlock(gtx, f, st, b, idx, unit.Sp(19), true, a.ui.p.Text)
	case "subheader":
		return a.ivRichBlock(gtx, f, st, b, idx, unit.Sp(16), true, a.ui.p.Text)
	case "paragraph":
		return a.ivRichBlock(gtx, f, st, b, idx, unit.Sp(15), false, a.ui.p.Text)
	case "footer":
		return a.ivRichBlock(gtx, f, st, b, idx, unit.Sp(12), false, a.ui.p.TextDim)
	case "preformatted":
		return a.ivPreBlock(gtx, b)
	case "author_date":
		return a.ivAuthorDate(gtx, st, b)
	case "divider":
		return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			h := gtx.Dp(unit.Dp(1))
			stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, h)}.Push(gtx.Ops)
			paint.FillShape(gtx.Ops, a.ui.p.SurfaceHi, clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, h)}.Op())
			stack.Pop()
			return layout.Dimensions{Size: image.Pt(gtx.Constraints.Max.X, h)}
		})
	case "anchor":
		return layout.Dimensions{}
	case "blockquote":
		return a.ivQuoteBlock(gtx, f, st, b, idx)
	case "pullquote":
		return a.ivPullQuoteBlock(gtx, f, st, b, idx)
	case "list":
		return a.ivListBlock(gtx, f, st, b, idx)
	case "ordered_list":
		return a.ivOrderedListBlock(gtx, f, st, b, idx)
	case "photo", "cover":
		return a.ivPhotoBlock(gtx, st, b)
	case "video":
		return a.ivVideoBlock(gtx, st, b)
	case "audio":
		return a.ivAudioBlock(gtx, st, b)
	case "embed":
		return a.ivEmbedBlock(gtx, st, b)
	case "embed_post":
		return a.ivEmbedPostBlock(gtx, f, st, b)
	case "collage":
		return a.ivCollageBlock(gtx, f, st, b)
	case "slideshow":
		return a.ivSlideshowBlock(gtx, f, st, b, idx)
	case "details":
		return a.ivDetailsBlock(gtx, f, st, b, idx)
	case "related":
		return a.ivRelatedBlock(gtx, f, st, b, idx)
	case "table":
		return a.ivTableBlock(gtx, b)
	case "channel":
		return a.ivChannelBlock(gtx, b)
	case "map":
		return a.ivMapBlock(gtx, st, b)
	}
	// cover wraps one inner block; render it directly.
	if b.Type == "cover" && len(b.Items) > 0 {
		return a.ivBlockWidget(gtx, f, st, &b.Items[0], idx)
	}
	return layout.Dimensions{}
}

// ivRichBlock renders a rich-text block through the message renderer
// (wrapping + link taps + mono pills).
func (a *App) ivRichBlock(gtx layout.Context, f frame, st *ivState, b *ivBlock, idx int, size unit.Sp, bold bool, col color.NRGBA) layout.Dimensions {
	text, ents := ivSpanEntities(ivRichSpans(b.Text))
	if text == "" {
		return layout.Dimensions{}
	}
	segs := parseRichSegments(text, ents)
	if len(segs) == 0 {
		lbl := a.ui.Label(size, text)
		if bold {
			lbl.Font.Weight = font.Bold
		}
		lbl.Color = col
		return lbl.Layout(gtx)
	}
	m := engine.CachedMessage{
		AccountID:   st.accountID,
		ChatID:      "iv",
		MsgID:       "iv|" + st.url + "|" + strconv.Itoa(idx),
		ContentText: text,
	}
	if raw, err := json.Marshal(ents); err == nil {
		m.ContentRich = raw
	}
	if st.page != nil && st.page.RTL {
		return layout.E.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return a.flowRich(gtx, m, size, col, a.ui.p.Background, segs, true)
		})
	}
	return a.flowRich(gtx, m, size, col, a.ui.p.Background, segs, true)
}

// ivPreBlock: mono panel (SurfaceHi rounded, Go Mono).
func (a *App) ivPreBlock(gtx layout.Context, b *ivBlock) layout.Dimensions {
	spans := ivRichSpans(b.Text)
	var sb strings.Builder
	for _, s := range spans {
		sb.WriteString(s.Text)
	}
	if sb.Len() == 0 {
		return layout.Dimensions{}
	}
	return roundedFill(gtx, a.ui.p.SurfaceHi, unit.Dp(8), func(gtx layout.Context) layout.Dimensions {
		return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Label(unit.Sp(13), sb.String())
			lbl.Font.Typeface = "Go Mono"
			return lbl.Layout(gtx)
		})
	})
}

// ivAuthorDate: "Author · Sep 13, 2026" dim row.
func (a *App) ivAuthorDate(gtx layout.Context, st *ivState, b *ivBlock) layout.Dimensions {
	var spans []ivSpan
	spans = append(spans, ivRichSpans(b.Author)...)
	date := ""
	if b.Date > 0 {
		date = time.Unix(b.Date, 0).Format("Jan 2, 2006")
	}
	text, ents := ivSpanEntities(spans)
	if date != "" {
		if text != "" {
			text += " · "
		}
		text += date
	}
	if text == "" {
		return layout.Dimensions{}
	}
	if len(ents) > 0 {
		segs := parseRichSegments(text, ents)
		if len(segs) > 0 {
			m := engine.CachedMessage{AccountID: st.accountID, ChatID: "iv", MsgID: "iv|ad|" + st.url, ContentText: text}
			if raw, err := json.Marshal(ents); err == nil {
				m.ContentRich = raw
			}
			return a.flowRich(gtx, m, unit.Sp(12), a.ui.p.TextDim, a.ui.p.Background, segs, true)
		}
	}
	lbl := a.ui.Label(unit.Sp(12), text)
	lbl.Color = a.ui.p.TextDim
	return lbl.Layout(gtx)
}

// ivQuoteBlock: accent left bar + indented text + caption.
func (a *App) ivQuoteBlock(gtx layout.Context, f frame, st *ivState, b *ivBlock, idx int) layout.Dimensions {
	children := []layout.FlexChild{}
	if t, _ := ivSpanEntities(ivRichSpans(b.Text)); t != "" {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.ivRichBlock(gtx, f, st, b, idx, unit.Sp(14), false, a.ui.p.Text)
		}))
	}
	if c, _ := ivSpanEntities(ivRichSpans(b.Caption)); c != "" {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return a.ivRichBlock(gtx, f, st, &ivBlock{Type: "caption", Text: b.Caption}, idx, unit.Sp(12), false, a.ui.p.TextDim)
			})
		}))
	}
	if len(children) == 0 {
		return layout.Dimensions{}
	}
	return layout.Inset{Left: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		bar := gtx.Dp(unit.Dp(3))
		w := gtx.Constraints.Max.X
		body := layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			gtx.Constraints.Max.X = w - bar - gtx.Dp(unit.Dp(10))
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
		})
		stack := clip.Rect{Max: image.Pt(bar, body.Size.Y)}.Push(gtx.Ops)
		paint.FillShape(gtx.Ops, a.ui.p.Accent, clip.Rect{Max: image.Pt(bar, body.Size.Y)}.Op())
		stack.Pop()
		return body
	})
}

// ivPullQuoteBlock: centered large quote + attribution.
func (a *App) ivPullQuoteBlock(gtx layout.Context, f frame, st *ivState, b *ivBlock, idx int) layout.Dimensions {
	children := []layout.FlexChild{}
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return a.ivRichBlock(gtx, f, st, b, idx, unit.Sp(18), false, a.ui.p.Text)
			})
		})
	}))
	if c, _ := ivSpanEntities(ivRichSpans(b.Caption)); c != "" {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return a.ivRichBlock(gtx, f, st, &ivBlock{Type: "caption", Text: b.Caption}, idx, unit.Sp(12), false, a.ui.p.TextDim)
			})
		}))
	}
	return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx, children...)
}

// ivListBlock: bullet rows (text or nested blocks).
func (a *App) ivListBlock(gtx layout.Context, f frame, st *ivState, b *ivBlock, idx int) layout.Dimensions {
	var rows []layout.FlexChild
	for _, li := range b.ListItems {
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.ivListRow(gtx, f, st, li, "•")
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
}

// ivOrderedListBlock: numbered rows.
func (a *App) ivOrderedListBlock(gtx layout.Context, f frame, st *ivState, b *ivBlock, idx int) layout.Dimensions {
	var rows []layout.FlexChild
	for i, li := range b.ListItems {
		mark := strconv.Itoa(li.Num)
		if mark == "0" {
			mark = strconv.Itoa(i + 1)
		}
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.ivListRow(gtx, f, st, li, mark+".")
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
}

// ivListRow: marker column + content column.
func (a *App) ivListRow(gtx layout.Context, f frame, st *ivState, li ivListItem, mark string) layout.Dimensions {
	return layout.Inset{Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Label(unit.Sp(15), mark)
				lbl.Color = a.ui.p.Accent
				return layout.Inset{Right: unit.Dp(8), Top: unit.Dp(1)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return lbl.Layout(gtx)
				})
			}),
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				if li.HasBlocks {
					var rows []layout.FlexChild
					for j := range li.Blocks {
						jj := j
						rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return a.ivBlockWidget(gtx, f, st, &li.Blocks[jj], jj)
						}))
					}
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
				}
				return a.ivRichBlock(gtx, f, st, &ivBlock{Type: "li", Text: li.Text}, 0, unit.Sp(15), false, a.ui.p.Text)
			}),
		)
	})
}

// ivPhotoKey builds the media-image cache key for an IV photo.
func ivPhotoKey(photoID int64) string {
	return "ivphoto:" + strconv.FormatInt(photoID, 10)
}

// ivPhotoBlock: full-width image (thumb first, async full decode).
func (a *App) ivPhotoBlock(gtx layout.Context, st *ivState, b *ivBlock) layout.Dimensions {
	maxW := gtx.Constraints.Max.X
	if maxW <= 0 {
		return layout.Dimensions{}
	}
	// Aspect-true height from the reported dims (cap 420dp).
	h := maxW
	if b.W > 0 && b.H > 0 {
		h = maxW * b.H / b.W
	}
	if capPx := gtx.Dp(unit.Dp(420)); h > capPx && h > 0 {
		h = capPx
	}
	img := a.ivPhotoImage(st, b)
	var d layout.Dimensions
	if img != nil {
		d = drawImageScaled(gtx, img, maxW, h, gtx.Dp(unit.Dp(8)))
	} else if b.ThumbB64 != "" || (b.Extra != "" && b.PhotoID != 0) {
		d = layout.Dimensions{Size: image.Pt(maxW, h)} // decode in flight
	} else {
		return layout.Dimensions{}
	}
	if c, _ := ivSpanEntities(ivRichSpans(b.Caption)); c != "" {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions { return d }),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(12), c)
						lbl.Color = a.ui.p.TextDim
						return lbl.Layout(gtx)
					})
				})
			}),
		)
	}
	return d
}

// ivPhotoImage resolves the photo bitmap: full file when downloaded, the
// stripped thumb meanwhile; kicks the async chains.
func (a *App) ivPhotoImage(st *ivState, b *ivBlock) *image.RGBA {
	if b.PhotoID == 0 {
		return nil
	}
	key := ivPhotoKey(b.PhotoID)
	if img := mediaImgs.get(key); img != nil {
		return img
	}
	if b.ThumbB64 != "" {
		if img := mediaImgs.get("thumb:" + b.ThumbB64); img != nil {
			return img
		}
		a.decodeThumbAsync("thumb:"+b.ThumbB64, b.ThumbB64)
	}
	// Async full download + decode, once per photo.
	ivDocMu.Lock()
	busy := ivDocDone[key]
	if !busy {
		ivDocDone[key] = true
	}
	ivDocMu.Unlock()
	if !busy {
		go func() {
			data, err := a.eng.DownloadIVPhoto(st.accountID, b.PhotoID, b.Extra)
			if err != nil {
				return
			}
			var env struct {
				Path string `json:"path"`
			}
			if json.Unmarshal(data, &env) != nil || env.Path == "" {
				return
			}
			a.decodeImageAsync(key, func() ([]byte, error) { return os.ReadFile(env.Path) })
		}()
	}
	return nil
}

// ivVideoBlock: video card — tap downloads via the engine's IV document
// downloader and hands off to the system player (slice-86 pattern; no
// in-app decode, §1.10).
func (a *App) ivVideoBlock(gtx layout.Context, st *ivState, b *ivBlock) layout.Dimensions {
	if b.VideoID == 0 {
		return layout.Dimensions{}
	}
	key := "ivvid:" + strconv.FormatInt(b.VideoID, 10)
	btn := a.ivDocClickable(key)
	if btn.Clicked(gtx) {
		a.ivDownloadDoc(st, key, b.VideoID, b.Extra, b.Mime)
	}
	return btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.SurfaceHi, unit.Dp(8), func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(12)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				sub := ""
				if b.Duration > 0 {
					sub = fmtDur(b.Duration)
				} else if b.Size > 0 {
					sub = fmtBytes(b.Size)
				}
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.ivDocIcon(gtx, st, key, iconAVPlayCircle)
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						title := b.Filename
						if title == "" {
							title = "Video"
						}
						var rows []layout.FlexChild
						rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(14), title)
							lbl.MaxLines = 1
							return lbl.Layout(gtx)
						}))
						if sub != "" {
							rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), sub+" · tap to play")
								lbl.MaxLines = 1
								return lbl.Layout(gtx)
							}))
						}
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
					}),
				)
			})
		})
	})
}

// ivAudioBlock: audio card — same handoff pattern.
func (a *App) ivAudioBlock(gtx layout.Context, st *ivState, b *ivBlock) layout.Dimensions {
	if b.AudioID == 0 {
		return layout.Dimensions{}
	}
	key := "ivaud:" + strconv.FormatInt(b.AudioID, 10)
	btn := a.ivDocClickable(key)
	if btn.Clicked(gtx) {
		a.ivDownloadDoc(st, key, b.AudioID, b.Extra, b.Mime)
	}
	return btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.SurfaceHi, unit.Dp(8), func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(12)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				title := b.Filename
				if title == "" {
					title = "Audio"
				}
				sub := ""
				if b.Duration > 0 {
					sub = fmtDur(b.Duration)
				}
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.ivDocIcon(gtx, st, key, iconAVNote)
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						var rows []layout.FlexChild
						rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(14), title)
							lbl.MaxLines = 1
							return lbl.Layout(gtx)
						}))
						if sub != "" {
							rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), sub+" · tap to play")
								lbl.MaxLines = 1
								return lbl.Layout(gtx)
							}))
						}
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
					}),
				)
			})
		})
	})
}

// ivDocIcon: the media glyph, dimmed while its download runs.
func (a *App) ivDocIcon(gtx layout.Context, st *ivState, key string, icon *widget.Icon) layout.Dimensions {
	ivDocMu.Lock()
	busy := st.docBusy[key]
	ivDocMu.Unlock()
	col := a.ui.p.Accent
	if busy {
		col = a.ui.p.TextDim
	}
	return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(28))
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(28))
		return icon.Layout(gtx, col)
	})
}

// ivDownloadDoc: async download + system-player handoff, once at a time.
func (a *App) ivDownloadDoc(st *ivState, key string, docID int64, extra, mime string) {
	ivDocMu.Lock()
	if st.docBusy == nil {
		st.docBusy = map[string]bool{}
	}
	if st.docBusy[key] {
		ivDocMu.Unlock()
		return
	}
	st.docBusy[key] = true
	ivDocMu.Unlock()
	a.invalidate()
	go func() {
		data, err := a.eng.DownloadIVDocument(st.accountID, docID, extra, mime)
		ivDocMu.Lock()
		delete(st.docBusy, key)
		ivDocMu.Unlock()
		a.invalidate()
		if err != nil {
			a.setToast("Download failed: " + err.Error())
			return
		}
		var env struct {
			Path string `json:"path"`
		}
		if json.Unmarshal(data, &env) != nil || env.Path == "" {
			a.setToast("Download failed: no file")
			return
		}
		openExternalAsync(env.Path, func(e error) {
			if e != nil {
				a.setToast("Open failed: " + e.Error())
			}
		})
	}()
}

// ivEmbedBlock: embed card → browser (no webview, §1.10 honest scope).
func (a *App) ivEmbedBlock(gtx layout.Context, st *ivState, b *ivBlock) layout.Dimensions {
	if b.URL == "" && b.HTML == "" {
		return layout.Dimensions{}
	}
	btn := a.ivDocClickable("ivembed:" + b.URL + b.HTML)
	if btn.Clicked(gtx) {
		u := b.URL
		if u == "" {
			u = st.url
		}
		openExternalAsync(u, func(err error) {
			if err != nil {
				a.setToast("Open link failed: " + err.Error())
			}
		})
	}
	return btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.SurfaceHi, unit.Dp(8), func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(12)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							gtx.Constraints.Max.X = gtx.Dp(unit.Dp(24))
							gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(24))
							return iconContentLink.Layout(gtx, a.ui.p.Accent)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						var rows []layout.FlexChild
						rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(14), "Embedded content")
							lbl.MaxLines = 1
							return lbl.Layout(gtx)
						}))
						rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							u := b.URL
							if u == "" {
								u = ivHostOf(st.url)
							}
							lbl := a.ui.Dim(unit.Sp(11), u+" · opens in browser")
							lbl.MaxLines = 1
							return lbl.Layout(gtx)
						}))
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
					}),
				)
			})
		})
	})
}

// ivMapBlock: the IV map card — location glyph + zoom label, opens the
// original page in the browser (no tile fetch for IV maps).
func (a *App) ivMapBlock(gtx layout.Context, st *ivState, b *ivBlock) layout.Dimensions {
	btn := a.ivDocClickable("ivmap:" + st.url)
	if btn.Clicked(gtx) {
		openExternalAsync(st.url, func(err error) {
			if err != nil {
				a.setToast("Open link failed: " + err.Error())
			}
		})
	}
	return btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.SurfaceHi, unit.Dp(8), func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(12)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							gtx.Constraints.Max.X = gtx.Dp(unit.Dp(24))
							gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(24))
							return iconMapsPlace.Layout(gtx, a.ui.p.Accent)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(14), "Map")
						return lbl.Layout(gtx)
					}),
				)
			})
		})
	})
}

// ivEmbedPostBlock: author + date header + nested blocks + caption.
func (a *App) ivEmbedPostBlock(gtx layout.Context, f frame, st *ivState, b *ivBlock) layout.Dimensions {
	var rows []layout.FlexChild
	if b.AuthorName != "" || b.Date > 0 {
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			sub := b.AuthorName
			if b.Date > 0 {
				if sub != "" {
					sub += " · "
				}
				sub += time.Unix(b.Date, 0).Format("Jan 2, 2006")
			}
			lbl := a.ui.Label(unit.Sp(12), sub)
			lbl.Color = a.ui.p.TextDim
			return lbl.Layout(gtx)
		}))
	}
	for j := range b.Items {
		jj := j
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.ivBlockWidget(gtx, f, st, &b.Items[jj], jj)
		}))
	}
	if c, _ := ivSpanEntities(ivRichSpans(b.Caption)); c != "" {
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Label(unit.Sp(12), c)
				lbl.Color = a.ui.p.TextDim
				return lbl.Layout(gtx)
			})
		}))
	}
	if len(rows) == 0 {
		return layout.Dimensions{}
	}
	return roundedFill(gtx, a.ui.p.SurfaceHi, unit.Dp(8), func(gtx layout.Context) layout.Dimensions {
		return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
		})
	})
}

// ivCollageBlock: 2-column photo grid.
func (a *App) ivCollageBlock(gtx layout.Context, f frame, st *ivState, b *ivBlock) layout.Dimensions {
	var items []*ivBlock
	for i := range b.Items {
		if b.Items[i].Type == "photo" || b.Items[i].Type == "video" {
			items = append(items, &b.Items[i])
		}
	}
	if len(items) == 0 {
		return layout.Dimensions{}
	}
	perRow := 2
	var rows []layout.FlexChild
	for i := 0; i < len(items); i += perRow {
		var cells []layout.FlexChild
		for j := i; j < i+perRow && j < len(items); j++ {
			jj := j
			cells = append(cells, layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Right: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return a.ivBlockWidget(gtx, f, st, items[jj], jj)
				})
			}))
		}
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, cells...)
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
}

// ivSlideshowBlock: one item at a time + prev/next chevrons + counter.
func (a *App) ivSlideshowBlock(gtx layout.Context, f frame, st *ivState, b *ivBlock, idx int) layout.Dimensions {
	if len(b.Items) == 0 {
		return layout.Dimensions{}
	}
	path := strconv.Itoa(idx)
	cur := st.slideAt(path)
	if cur >= len(b.Items) {
		cur = 0
	}
	prev := &a.wid.ivSlidePrev
	next := &a.wid.ivSlideNext
	if prev.Clicked(gtx) {
		st.setSlideAt(path, (cur-1+len(b.Items))%len(b.Items))
	}
	if next.Clicked(gtx) {
		st.setSlideAt(path, (cur+1)%len(b.Items))
	}
	cur = st.slideAt(path)
	return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.ui.IconButton(prev, iconNavChevronLeft, "Previous").Layout(gtx)
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.ivBlockWidget(gtx, f, st, &b.Items[cur], idx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(11), fmt.Sprintf("%d / %d", cur+1, len(b.Items)))
						return lbl.Layout(gtx)
					})
				}),
			)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.ui.IconButton(next, iconNavChevronRight, "Next").Layout(gtx)
		}),
	)
}

// ivDetailsBlock: collapsible section (chevron + title; blocks when open).
func (a *App) ivDetailsBlock(gtx layout.Context, f frame, st *ivState, b *ivBlock, idx int) layout.Dimensions {
	title, _ := ivSpanEntities(ivRichSpans(b.Text))
	btn := a.ivDocClickable("ivdet:" + strconv.Itoa(idx))
	if btn.Clicked(gtx) {
		st.setDetailsOpen(idx, !st.detailsOpenAt(idx, b.Open))
	}
	open := st.detailsOpenAt(idx, b.Open)
	chev := iconNavChevronRight
	var rows []layout.FlexChild
	rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					gtx.Constraints.Max.X = gtx.Dp(unit.Dp(20))
					gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(20))
					return chev.Layout(gtx, a.ui.p.TextDim)
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(15), title)
					lbl.MaxLines = 1
					return lbl.Layout(gtx)
				}),
			)
		})
	}))
	if open {
		for j := range b.Items {
			jj := j
			rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return a.ivBlockWidget(gtx, f, st, &b.Items[jj], jj)
				})
			}))
		}
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
}

// ivRelatedBlock: related-article rows — tap navigates inside the reader.
func (a *App) ivRelatedBlock(gtx layout.Context, f frame, st *ivState, b *ivBlock, idx int) layout.Dimensions {
	if len(b.Articles) == 0 {
		return layout.Dimensions{}
	}
	title, _ := ivSpanEntities(ivRichSpans(b.Text))
	if title == "" {
		title = "Related articles"
	}
	var rows []layout.FlexChild
	rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Label(unit.Sp(13), strings.ToUpper(title))
			lbl.Color = a.ui.p.TextDim
			return lbl.Layout(gtx)
		})
	}))
	for i, art := range b.Articles {
		i, art := i, art
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			btn := a.ivDocClickable("ivrel:" + st.url + ":" + strconv.Itoa(i))
			if btn.Clicked(gtx) {
				a.ivOpenRelated(st.accountID, art.URL)
			}
			return layout.Inset{Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return roundedFill(gtx, a.ui.p.SurfaceHi, unit.Dp(8), func(gtx layout.Context) layout.Dimensions {
						return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							var mr []layout.FlexChild
							t := art.Title
							if t == "" {
								t = art.URL
							}
							mr = append(mr, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), t)
								lbl.MaxLines = 2
								return lbl.Layout(gtx)
							}))
							if art.Desc != "" {
								mr = append(mr, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Dim(unit.Sp(12), art.Desc)
									lbl.MaxLines = 2
									return lbl.Layout(gtx)
								}))
							}
							sub := ivHostOf(art.URL)
							if art.Author != "" {
								sub = art.Author + " · " + sub
							}
							mr = append(mr, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), sub)
								lbl.MaxLines = 1
								return lbl.Layout(gtx)
							}))
							return layout.Flex{Axis: layout.Vertical}.Layout(gtx, mr...)
						})
					})
				})
			})
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
}

// ivTableBlock: row grid — header bold, striped zebra, hairline borders.
func (a *App) ivTableBlock(gtx layout.Context, b *ivBlock) layout.Dimensions {
	if len(b.Rows) == 0 {
		return layout.Dimensions{}
	}
	// Column count = max cells-per-row (colspan aware).
	ncols := 1
	for _, r := range b.Rows {
		w := 0
		for _, c := range r {
			cs := c.Colspan
			if cs < 1 {
				cs = 1
			}
			w += cs
		}
		if w > ncols {
			ncols = w
		}
	}
	title, _ := ivSpanEntities(ivRichSpans(b.Text))
	var rows []layout.FlexChild
	if title != "" {
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Label(unit.Sp(13), title)
			lbl.Color = a.ui.p.TextDim
			return lbl.Layout(gtx)
		}))
	}
	for ri, r := range b.Rows {
		ri, r := ri, r
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			var cells []layout.FlexChild
			for _, c := range r {
				c := c
				cs := c.Colspan
				if cs < 1 {
					cs = 1
				}
				cells = append(cells, layout.Flexed(float32(cs), func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6), Left: unit.Dp(8), Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						text, _ := ivSpanEntities(ivRichSpans(c.Text))
						if text == "" {
							return layout.Dimensions{}
						}
						lbl := a.ui.Label(unit.Sp(13), text)
						if c.Header {
							lbl.Font.Weight = font.Bold
						}
						if c.AlignCenter {
							return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions { return lbl.Layout(gtx) })
						}
						if c.AlignRight {
							return layout.E.Layout(gtx, func(gtx layout.Context) layout.Dimensions { return lbl.Layout(gtx) })
						}
						return lbl.Layout(gtx)
					})
				}))
			}
			w := layout.Flex{Axis: layout.Horizontal}.Layout(gtx, cells...)
			if b.Bordered && ri < len(b.Rows)-1 {
				stack := clip.Rect{Max: image.Pt(w.Size.X, gtx.Dp(unit.Dp(1)))}.Push(gtx.Ops)
				paint.FillShape(gtx.Ops, a.ui.p.SurfaceHi, clip.Rect{Max: image.Pt(w.Size.X, gtx.Dp(unit.Dp(1)))}.Op())
				stack.Pop()
			}
			if b.Striped && ri%2 == 1 {
				stack := clip.Rect{Max: w.Size}.Push(gtx.Ops)
				paint.FillShape(gtx.Ops, blendSurface(a.ui.p.SurfaceHi, 0.5), clip.Rect{Max: w.Size}.Op())
				stack.Pop()
			}
			_ = ncols
			return w
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
}

// ivChannelBlock: channel reference card → the t.me deep link (the
// in-app resolver opens the chat).
func (a *App) ivChannelBlock(gtx layout.Context, b *ivBlock) layout.Dimensions {
	if b.ChannelTitle == "" && b.Username == "" {
		return layout.Dimensions{}
	}
	btn := a.ivDocClickable("ivchan:" + strconv.FormatInt(b.ChannelID, 10))
	if btn.Clicked(gtx) {
		if b.Username != "" {
			a.openLinkExternal("https://t.me/" + b.Username)
		} else {
			a.setToast("Channel link unavailable")
		}
	}
	return btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.SurfaceHi, unit.Dp(8), func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				title := b.ChannelTitle
				if title == "" {
					title = "@" + b.Username
				}
				sub := "Channel"
				if b.Username != "" {
					sub = "@" + b.Username
				}
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.ui.Avatar(gtx, title, unit.Dp(40), dotNone)
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Label(unit.Sp(14), title)
									lbl.MaxLines = 1
									return lbl.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Dim(unit.Sp(11), sub)
									lbl.MaxLines = 1
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

// ivDocClickable pools the reader's clickables per key.
func (a *App) ivDocClickable(key string) *widget.Clickable {
	if c, ok := a.wid.ivClickables[key]; ok {
		return c
	}
	if len(a.wid.ivClickables) > 256 {
		a.wid.ivClickables = make(map[string]*widget.Clickable)
	}
	c := new(widget.Clickable)
	a.wid.ivClickables[key] = c
	return c
}

// ivHostOf: the URL's host (fallback: the URL itself).
func ivHostOf(raw string) string {
	if u, err := url.Parse(raw); err == nil && u.Hostname() != "" {
		return u.Hostname()
	}
	return raw
}

// blendSurface mixes a surface color toward the background by alpha.
func blendSurface(c color.NRGBA, alpha float32) color.NRGBA {
	return color.NRGBA{
		R: uint8(float32(c.R) * alpha),
		G: uint8(float32(c.G) * alpha),
		B: uint8(float32(c.B) * alpha),
		A: uint8(float32(c.A) * alpha),
	}
}

// ivDocMu guards the reader's once-per-doc maps and docBusy flags.
var ivDocMu sync.Mutex

// ivDocDone: one-shot IV photo downloads.
var ivDocDone = map[string]bool{}

// ivKeyTag is the reader's keyboard-event tag.
var ivKeyTag = new(bool)
