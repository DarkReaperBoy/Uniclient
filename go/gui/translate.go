package gui

import (
	"strings"

	"gioui.org/font"
	"gioui.org/layout"
	"gioui.org/unit"

	"uniclient/engine"
)

func (a *App) translateTargetOf() string {
	a.mu.Lock()
	t := a.transTarget
	a.mu.Unlock()
	if t == "" {
		return "en"
	}
	return t
}

func transKey(m *engine.CachedMessage) string {
	return m.AccountID + "|" + m.ChatID + "|" + m.MsgID
}

func (a *App) toggleTranslation(m *engine.CachedMessage) {
	if m == nil {
		return
	}
	key := transKey(m)
	a.mu.Lock()
	if _, shown := a.translations[key]; shown {
		delete(a.translations, key)
		a.mu.Unlock()
		a.invalidate()
		return
	}
	a.mu.Unlock()

	msg := *m
	text := strings.TrimSpace(msg.ContentText)
	go func() {
		out, err := a.eng.TranslateText(msg.AccountID, msg.ChatID, msg.MsgID, a.translateTargetOf(), text)
		if err != nil {
			a.setToast("Translate failed: " + err.Error())
			return
		}
		if strings.TrimSpace(out) == "" {
			a.setToast("No translation returned")
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

func (a *App) translationFor(m *engine.CachedMessage) (string, bool) {
	a.mu.Lock()
	defer a.mu.Unlock()
	t, ok := a.translations[transKey(m)]
	return t, ok
}

func (a *App) translationBlock(gtx layout.Context, m *engine.CachedMessage) layout.Dimensions {
	t, ok := a.translationFor(m)
	if !ok || t == "" {
		return layout.Dimensions{}
	}
	return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Bottom: unit.Dp(1)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(10), "Translated")
					lbl.Color = a.ui.p.TextFaint
					return lbl.Layout(gtx)
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(14), t)
				lbl.Font.Style = font.Italic
				return lbl.Layout(gtx)
			}),
		)
	})
}
