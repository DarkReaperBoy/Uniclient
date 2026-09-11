package gui

// powersave.go — slice 135: power saving made real (tdesktop semantics).
// The engine's SetPowerSaving surface existed but nothing consumed it; now
// the GUI gates its chat animation loops — stickers/dice and inline custom
// emoji render their FIRST frame statically with no frame re-arm while the
// matching PowerSaving flag (or force-all) is on. The settings row persists
// through AppConfig like every other toggle.

// PowerSaving flag bits (tdesktop PowerSaving::Flags values).
const (
	psFlagStickersPanel = 1 << 0
	psFlagStickersChat  = 1 << 1
	psFlagEmojiPanel    = 1 << 2
	psFlagEmojiChat     = 1 << 3
	psFlagGifsPanel     = 1 << 4
	psFlagGifsChat      = 1 << 5
)

// psClass is the animation class a render site belongs to.
type psClass int

const (
	psClassStickers psClass = iota // sticker bubbles + dice
	psClassEmoji                   // inline custom emoji
)

// powerSavingBlocks reports whether chat animations of one class are
// blocked by the current power-saving state (force-all treats every flag
// as enabled — AyuGram PowerSaving::SetForceAll semantics). Pure —
// unit-tested.
func powerSavingBlocks(flags int, forceAll bool, class psClass) bool {
	if forceAll {
		return true
	}
	switch class {
	case psClassStickers:
		return flags&psFlagStickersChat != 0
	case psClassEmoji:
		return flags&psFlagEmojiChat != 0
	}
	return false
}

// powerSavingState mirrors the engine's stored flags for render gating.
type powerSavingState struct {
	flags    int
	forceAll bool
}

var powerSaving = powerSavingState{}

// psSet applies a new power-saving state and pushes it to the engine
// (which persists it in AppConfig — Init restores it).
func (a *App) psSet(flags int, forceAll bool) {
	powerSaving = powerSavingState{flags: flags, forceAll: forceAll}
	go a.eng.SetPowerSaving(flags, forceAll)
	a.invalidate()
}

// psLoad bootstraps the GUI state from the engine/config.
func (a *App) psLoad() {
	if a.eng == nil {
		return
	}
	if f, fa, ok := a.eng.GetPowerSaving(); ok {
		powerSaving = powerSavingState{flags: f, forceAll: fa}
	}
}
