package gui

import (
	"strings"

	"gioui.org/font"
	"gioui.org/layout"
	"gioui.org/unit"

	"uniclient/engine"
)

// Ayu translator (AyuGram parity, matrix "Ayu translator"): the message
// context menu gains Translate — the message text goes through the engine's
// translation pipeline (Telegram MT translate via TranslateFreeText, falling
// back to the message-bound TranslateText when the core lacks free-text
// support) and the result renders as an italic block under the bubble body.
// The menu entry toggles to "Hide translation" while one is shown.

// translateTo is the target language (AyuGram default = app language; the
// settings row lands with the language switch).
const translateTo = "en"

// transKey identifies one message's shown translation.
func transKey(m *engine.CachedMessage) string {
	return m.AccountID + "|" + m.ChatID + "|" + m.MsgID
}

// toggleTranslation shows or hides (and lazily fetches) a message's
// translation. Errors surface as toasts (unsupported platforms say so).
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
		out, err := a.eng.TranslateText(msg.AccountID, msg.ChatID, msg.MsgID, translateTo, text)
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

// translationFor returns the shown translation for a message ("" when none).
func (a *App) translationFor(m *engine.CachedMessage) (string, bool) {
	a.mu.Lock()
	defer a.mu.Unlock()
	t, ok := a.translations[transKey(m)]
	return t, ok
}

// translationBlock renders the translated text under the bubble body:
// a "Translated" caption + the italic text (AyuGram inline layout).
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
