package gui

// gui/dice.go — slice 125: dice messages render as animated .tgs stickers.
// The message's media row starts as a placeholder (application/x-dice); on
// first render the GUI asks the engine to resolve the dice pack document
// for the message's current value (EnsureDiceSticker rewrites the row and
// downloads through the normal pipeline). While rolling (value 0) the roll
// animation loops; once the value lands (message edit) the outcome document
// downloads and plays once, holding its final frame — tdesktop Dice
// behavior. Slot machines compose several reel stickers; UniClient shows
// the plain emoji + value text for those (honest, §1.10).

import (
	"encoding/json"

	"gioui.org/layout"
	"gioui.org/unit"

	"uniclient/engine"
)

// diceInfo is a message's parsed dice metadata.
type diceInfo struct {
	Emoji string
	Value int
}

// parseDiceMessage reads dice_emoji / dice_value from the message's raw
// envelope. Pure — unit-tested.
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

// diceAnimated reports whether this dice emoji plays through the lottie
// path (the slot machine's multi-reel composition stays textual).
func diceAnimated(emoji string) bool {
	switch emoji {
	case "🎲", "🎯", "⚽", "🏀":
		return true
	}
	return false
}

// diceHoldLastFrame: outcome animations play once and rest on the value's
// final frame; the rolling intro (value 0) loops until the edit lands.
func diceHoldLastFrame(value int) bool {
	return value != 0
}

// ensureDiceSticker kicks the engine's dice resolution once per
// message+value (value swaps re-fire after the edit lands). Guarded like
// the photo auto-download; failures re-arm on the next frame.
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
			delete(a.autoDl, guard) // retryable
			a.mu.Unlock()
		}
	}()
}

// diceFallback renders the honest pre-download state: the game emoji
// itself at sticker scale (the notoemoji font covers all four games).
func (a *App) diceFallback(gtx layout.Context, info diceInfo, state int) layout.Dimensions {
	lbl := a.ui.Dim(unit.Sp(64), info.Emoji)
	if state == engine.DownloadFailed {
		lbl.Color = a.ui.p.Error
	}
	return lbl.Layout(gtx)
}
