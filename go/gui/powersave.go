package gui

const (
	psFlagStickersPanel = 1 << 0
	psFlagStickersChat  = 1 << 1
	psFlagEmojiPanel    = 1 << 2
	psFlagEmojiChat     = 1 << 3
	psFlagGifsPanel     = 1 << 4
	psFlagGifsChat      = 1 << 5
)

type psClass int

const (
	psClassStickers psClass = iota
	psClassEmoji
	psClassVideo
)

func powerSavingBlocks(flags int, forceAll bool, class psClass) bool {
	if forceAll {
		return true
	}
	switch class {
	case psClassStickers:
		return flags&psFlagStickersChat != 0
	case psClassEmoji:
		return flags&psFlagEmojiChat != 0
	case psClassVideo:
		return flags&psFlagGifsChat != 0
	}
	return false
}

type powerSavingState struct {
	flags    int
	forceAll bool
}

var powerSaving = powerSavingState{}

func (a *App) psSet(flags int, forceAll bool) {
	powerSaving = powerSavingState{flags: flags, forceAll: forceAll}
	go a.eng.SetPowerSaving(flags, forceAll)
	a.invalidate()
}

func (a *App) psLoad() {
	if a.eng == nil {
		return
	}
	if f, fa, ok := a.eng.GetPowerSaving(); ok {
		powerSaving = powerSavingState{flags: f, forceAll: fa}
	}
}
