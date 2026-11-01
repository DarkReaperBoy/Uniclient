package gui

import (
	"encoding/json"

	"gioui.org/layout"
	"gioui.org/unit"

	"uniclient/engine"
)

type diceInfo struct {
	Emoji string
	Value int
}

func parseDiceMessage(m *engine.CachedMessage) (diceInfo, bool) {
	if m == nil || len(m.ContentRaw) == 0 {
		return diceInfo{}, false
	}
	var env struct {
		Extra struct {
			DiceEmoji string `json:"dice_emoji"`
			DiceValue int    `json:"dice_value"`
		} `json:"extra"`
	}
	if err := json.Unmarshal(m.ContentRaw, &env); err != nil {
		return diceInfo{}, false
	}
	if env.Extra.DiceEmoji == "" {
		return diceInfo{}, false
	}
	return diceInfo{Emoji: env.Extra.DiceEmoji, Value: env.Extra.DiceValue}, true
}

func diceAnimated(emoji string) bool {
	switch emoji {
	case "🎲", "🎯", "⚽", "🏀":
		return true
	}
	return false
}

func diceHoldLastFrame(value int) bool {
	return value != 0
}

func (a *App) ensureDiceSticker(m *engine.CachedMessage) {
	if m == nil {
		return
	}
	info, ok := parseDiceMessage(m)
	if !ok || !diceAnimated(info.Emoji) {
		return
	}
	guard := m.MsgID + "|dice|" + itoa(info.Value)
	if !a.markAutoDl(guard) {
		return
	}
	msg := *m
	go func() {
		if err := a.eng.EnsureDiceSticker(msg.AccountID, msg.ChatID, msg.MsgID); err != nil {
			a.mu.Lock()
			delete(a.autoDl, guard)
			a.mu.Unlock()
		}
	}()
}

func (a *App) diceFallback(gtx layout.Context, info diceInfo, state int) layout.Dimensions {
	lbl := a.ui.Dim(unit.Sp(64), info.Emoji)
	if state == engine.DownloadFailed {
		lbl.Color = a.ui.p.Error
	}
	return lbl.Layout(gtx)
}
