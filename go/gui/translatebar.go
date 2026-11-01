package gui

import (
	"strings"

	"gioui.org/font"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/unit"
	"gioui.org/widget/material"

	"uniclient/engine"
)

type transLang struct {
	code string
	name string
}

var transLangs = []transLang{
	{"en", "English"},
	{"ru", "Russian"},
	{"uk", "Ukrainian"},
	{"de", "German"},
	{"es", "Spanish"},
	{"fr", "French"},
	{"it", "Italian"},
	{"pt", "Portuguese"},
	{"nl", "Dutch"},
	{"pl", "Polish"},
	{"tr", "Turkish"},
	{"ar", "Arabic"},
	{"fa", "Persian"},
	{"he", "Hebrew"},
	{"hi", "Hindi"},
	{"id", "Indonesian"},
	{"zh", "Chinese"},
	{"ja", "Japanese"},
	{"ko", "Korean"},
	{"vi", "Vietnamese"},
}

func transLangName(code string) string {
	for _, l := range transLangs {
		if l.code == code {
			return l.name
		}
	}
	if code != "" {
		return code
	}
	return "English"
}

func normalizeTransTarget(code string) string {
	if code == "" {
		return "en"
	}
	for _, l := range transLangs {
		if l.code == code {
			return code
		}
	}
	return "en"
}

func transChatKey(accountID, chatID string) string {
	return accountID + "|" + chatID
}

func chatTranslateOn(f frame, k *chatKey) bool {
	if k == nil {
		return false
	}
	return f.transChatOn[transChatKey(k.AccountID, k.ChatID)]
}

func (a *App) toggleChatTranslate(k chatKey) {
	key := transChatKey(k.AccountID, k.ChatID)
	a.mu.Lock()
	if a.transChatOn == nil {
		a.transChatOn = make(map[string]bool)
	}
	on := !a.transChatOn[key]
	a.transChatOn[key] = on
	if !on {
		a.transAsked = make(map[string]bool)
	}
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) setTransTarget(code string) {
	code = normalizeTransTarget(code)
	a.mu.Lock()
	a.transPickerOpen = false
	a.transTarget = code
	a.transAsked = make(map[string]bool)
	a.translations = make(map[string]string)
	a.mu.Unlock()
	a.invalidate()
	go func() {
		if err := a.eng.UpdateConfigFromBridge(&engine.ConfigChanges{TranslateTarget: code}); err != nil {
			a.setToast("Translate language not saved: " + err.Error())
		}
	}()
}

func (a *App) ensureAutoTranslation(m *engine.CachedMessage) {
	if m == nil || m.IsService {
		return
	}
	text := strings.TrimSpace(m.ContentText)
	if text == "" || pollIsBody(m) {
		return
	}
	key := transKey(m)
	a.mu.Lock()
	target := a.transTarget
	if target == "" {
		target = "en"
	}
	if _, done := a.translations[key]; done {
		a.mu.Unlock()
		return
	}
	if a.transAsked == nil {
		a.transAsked = make(map[string]bool)
	}
	if a.transAsked[key] {
		a.mu.Unlock()
		return
	}
	a.transAsked[key] = true
	a.mu.Unlock()

	msg := *m
	go func() {
		out, err := a.eng.TranslateText(msg.AccountID, msg.ChatID, msg.MsgID, target, text)
		if err != nil || strings.TrimSpace(out) == "" {
			return
		}
		a.mu.Lock()
		if a.translations == nil {
			a.translations = make(map[string]string)
		}
		a.translations[key] = out
		a.mu.Unlock()
		a.invalidate()
	}()
}

func (a *App) layoutTranslateBar(gtx layout.Context, f frame, k chatKey) layout.Dimensions {
	if a.wid.transBarOffBtn.Clicked(gtx) {
		a.toggleChatTranslate(k)
	}
	if a.wid.transBarLangBtn.Clicked(gtx) {
		a.mu.Lock()
		a.transPickerOpen = !a.transPickerOpen
		a.mu.Unlock()
		a.invalidate()
	}
	target := normalizeTransTarget(f.transTarget)

	var pickerDims layout.Dimensions
	if f.transPickerOpen {
		growClickables(&a.wid.transLangBtns, len(transLangs))
		rows := []layout.FlexChild{}
		for i := 0; i < len(transLangs); i += 4 {
			end := i + 4
			if end > len(transLangs) {
				end = len(transLangs)
			}
			var chips []layout.FlexChild
			for j := i; j < end; j++ {
				j := j
				if a.wid.transLangBtns[j].Clicked(gtx) {
					a.setTransTarget(transLangs[j].code)
				}
				chips = append(chips, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					active := transLangs[j].code == target
					bl := material.ButtonLayout(a.ui.Theme, &a.wid.transLangBtns[j])
					bl.CornerRadius = 12
					if active {
						bl.Background = a.ui.p.Accent
					} else {
						bl.Background = a.ui.p.Surface
					}
					return layout.Inset{Right: unit.Dp(6), Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(12), transLangs[j].name)
								if active {
									lbl.Color = a.ui.p.Background
								}
								return lbl.Layout(gtx)
							})
						})
					})
				}))
			}
			rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, chips...)
			}))
		}
		pickerDims = roundedFill(gtx, a.ui.p.SurfaceHi, 8, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
			})
		})
		gtx.Execute(op.InvalidateCmd{})
	}

	bar := layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return iconActionDone.Layout(gtx, a.ui.p.Accent)
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			btn := a.ui.TextButton(&a.wid.transBarLangBtn, "Translate to "+transLangName(target))
			btn.Color = a.ui.p.Accent
			btn.TextSize = unit.Sp(13)
			btn.Font.Weight = font.SemiBold
			return btn.Layout(gtx)
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			return layout.Dimensions{}
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			btn := a.ui.TextButton(&a.wid.transBarOffBtn, "Show original")
			btn.Color = a.ui.p.TextDim
			btn.TextSize = unit.Sp(13)
			return btn.Layout(gtx)
		}),
	)

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return bar
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if !f.transPickerOpen {
				return layout.Dimensions{}
			}
			return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12), Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return pickerDims
			})
		}),
	)
}
