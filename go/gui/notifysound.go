package gui

import (
	"log"
	"math"
	"sync"
	"time"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/audio"
	"uniclient/engine"
)

var notifySoundKinds = []string{"default", "gentle", "none"}

func notifySoundValid(kind string) bool {
	switch kind {
	case "default", "gentle", "none":
		return true
	}
	return false
}

func notifySoundLabel(kind string) string {
	switch kind {
	case "gentle":
		return "Gentle"
	case "none":
		return "No sound"
	}
	return "Default"
}

func notifySoundFor(cfgSound, chatSound string) string {
	if notifySoundValid(chatSound) && chatSound != "" {
		return chatSound
	}
	if notifySoundValid(cfgSound) && cfgSound != "" {
		return cfgSound
	}
	return "default"
}

func synthesizeNotifySound(kind string) []int16 {
	const rate = 48000
	switch kind {
	case "default":
		tone := func(freq float64, dur time.Duration, amp, decay float64) []int16 {
			n := int(float64(rate) * dur.Seconds())
			out := make([]int16, n)
			for i := range out {
				t := float64(i) / rate
				env := amp * math.Exp(-decay*t)
				out[i] = int16(env * math.Sin(2*math.Pi*freq*t) * 32767)
			}
			return out
		}
		a := tone(1318.51, 150*time.Millisecond, 0.45, 28)
		b := tone(1567.98, 300*time.Millisecond, 0.45, 16)
		total := len(a) + len(b) - int(float64(rate)*0.05)
		out := make([]int16, total)
		copy(out, a)
		off := len(a) - int(float64(rate)*0.05)
		for i, v := range b {
			if off+i < total {
				mix := int(out[off+i]) + int(v)
				if mix > 32767 {
					mix = 32767
				} else if mix < -32768 {
					mix = -32768
				}
				out[off+i] = int16(mix)
			}
		}
		fade := rate / 100
		for i := 0; i < fade && i < len(out); i++ {
			out[i] = int16(int(out[i]) * i / fade)
		}
		return out
	case "gentle":
		n := rate * 3 / 5
		out := make([]int16, n)
		const freq = 880
		const amp = 0.35
		const decay = 7
		attack := rate / 50
		for i := range out {
			t := float64(i) / rate
			env := amp * math.Exp(-decay*t)
			if i < attack {
				env *= float64(i) / float64(attack)
			}
			out[i] = int16(env * math.Sin(2*math.Pi*freq*t) * 32767)
		}
		return out
	}
	return nil
}

var (
	notifySndMu   sync.Mutex
	notifySndSess *audio.Session
	notifySndData []int16
	notifySndPos  int
)

func playNotifySound(kind string) {
	if kind == "none" || !audio.Available() {
		return
	}
	samples := synthesizeNotifySound(kind)
	if len(samples) == 0 {
		return
	}
	notifySndMu.Lock()
	defer notifySndMu.Unlock()
	if notifySndSess == nil {
		s, err := audio.Open()
		if err != nil {
			log.Printf("gui: notify sound: %v", err)
			return
		}
		notifySndSess = s
	}
	notifySndData = samples
	notifySndPos = 0
	notifySndSess.StopPlayback()
	if err := notifySndSess.StartPlayback(func(out []int16) {
		notifySndMu.Lock()
		n := copy(out, notifySndData[notifySndPos:])
		notifySndPos += n
		notifySndMu.Unlock()
		for i := n; i < len(out); i++ {
			out[i] = 0
		}
	}); err != nil {
		log.Printf("gui: notify sound: %v", err)
		return
	}
	time.AfterFunc(time.Duration(len(samples))*time.Second/48000+100*time.Millisecond, func() {
		notifySndMu.Lock()
		defer notifySndMu.Unlock()
		if notifySndSess != nil {
			notifySndSess.StopPlayback()
		}
	})
}

func (a *App) previewNotifySound(kind string) {
	go playNotifySound(kind)
}

func (a *App) applyConfigNotifySound(kind string) {
	if !notifySoundValid(kind) {
		return
	}
	k := kind
	go func() {
		c := &engine.ConfigChanges{NotifySound: &k}
		if err := a.eng.UpdateConfigFromBridge(c); err != nil {
			a.setToast("Settings: " + err.Error())
			return
		}
		a.refreshConfig()
	}()
}

type soundPickerState struct {
	mode      string
	accountID string
	chatID    string
	current   string
}

var (
	soundPickRowBtns  []widget.Clickable
	soundPickPlayBtn  []widget.Clickable
	soundPickResetBt  widget.Clickable
	soundPickCancelB  widget.Clickable
	notifySoundRowBtn []widget.Clickable
)

func (a *App) openSoundPickerGlobal() {
	a.mu.Lock()
	a.soundPicker = &soundPickerState{mode: "global", current: a.cfg.NotifySound}
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) openSoundPickerChat(accountID, chatID string) {
	d := &soundPickerState{mode: "chat", accountID: accountID, chatID: chatID}
	a.mu.Lock()
	a.soundPicker = d
	a.mu.Unlock()
	a.invalidate()
	go func() {
		kind, err := a.eng.GetChatNotifySound(accountID, chatID)
		if err != nil {
			kind = ""
		}
		a.mu.Lock()
		if cur := a.soundPicker; cur != nil && cur == d {
			cur.current = kind
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

func (a *App) closeSoundPicker() {
	a.mu.Lock()
	a.soundPicker = nil
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) applySoundChoice(kind string) {
	a.mu.Lock()
	d := a.soundPicker
	a.mu.Unlock()
	if d == nil {
		return
	}
	if d.mode == "chat" {
		go func() {
			if err := a.eng.SetChatNotifySound(d.accountID, d.chatID, kind); err != nil {
				a.setToast("Notifications: " + err.Error())
				return
			}
			a.setToast("Sound: " + notifySoundLabel(kind))
		}()
	} else {
		a.applyConfigNotifySound(kind)
		a.setToast("Sound: " + notifySoundLabel(kind))
	}
	a.mu.Lock()
	if cur := a.soundPicker; cur != nil && cur == d {
		cur.current = kind
	}
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) resetSoundOverride() {
	a.mu.Lock()
	d := a.soundPicker
	a.mu.Unlock()
	if d == nil || d.mode != "chat" {
		return
	}
	go func() {
		if err := a.eng.ResetPeerNotifySettings(d.accountID, d.chatID); err != nil {
			a.setToast("Notifications: " + err.Error())
			return
		}
		a.setToast("Notifications reset to defaults")
	}()
	a.closeSoundPicker()
}

func (a *App) layoutSoundPicker(gtx layout.Context, f frame) layout.Dimensions {
	d := f.soundPicker
	kinds := notifySoundKinds
	if d.mode == "chat" {
		kinds = append([]string{"default", "gentle", "none"}, "")
	}
	growClickables(&soundPickRowBtns, len(kinds))
	growClickables(&soundPickPlayBtn, len(kinds))
	if soundPickCancelB.Clicked(gtx) {
		a.closeSoundPicker()
	}
	if soundPickResetBt.Clicked(gtx) {
		a.resetSoundOverride()
	}
	for i, kind := range kinds {
		kind := kind
		if soundPickRowBtns[i].Clicked(gtx) {
			if kind == "" {
				a.resetSoundOverride()
			} else {
				a.applySoundChoice(kind)
			}
			continue
		}
		if soundPickPlayBtn[i].Clicked(gtx) && kind != "" {
			a.previewNotifySound(kind)
		}
	}

	title := "Notification Sound"
	if d.mode == "chat" {
		title = "Chat Notifications"
	}
	var children []layout.FlexChild
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(10), Bottom: unit.Dp(6), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					return a.ui.Label(unit.Sp(16), title).Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.SurfaceButton(&soundPickCancelB, "Close")
					return btn.Layout(gtx)
				}),
			)
		})
	}))
	if d.mode == "chat" && d.current == "" {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.settingRow(gtx, "Following the global setting", "")
		}))
	}
	for i, kind := range kinds {
		i, kind := i, kind
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			active := d.current == kind || (kind == "default" && d.current == "" && d.mode == "global")
			return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				bl := material.ButtonLayout(a.ui.Theme, &soundPickRowBtns[i])
				bl.Background = a.ui.p.Surface
				bl.CornerRadius = 10
				return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), notifySoundRowLabel(kind))
								if active {
									lbl.Color = a.ui.p.Accent
								}
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								if kind == "" {
									return layout.Dimensions{}
								}
								play := material.Button(a.ui.Theme, &soundPickPlayBtn[i], "Play")
								play.Background = a.ui.p.SurfaceHi
								play.Color = a.ui.p.TextDim
								play.TextSize = unit.Sp(12)
								play.CornerRadius = 8
								play.Inset = layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4), Left: unit.Dp(10), Right: unit.Dp(10)}
								return play.Layout(gtx)
							}),
						)
					})
				})
			})
		}))
	}
	if d.mode == "chat" {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(10), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.TextButton(&soundPickResetBt, "Reset to defaults")
				btn.Background = a.ui.p.Surface
				return btn.Layout(gtx)
			})
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func notifySoundRowLabel(kind string) string {
	if kind == "" {
		return "Reset to global setting"
	}
	return notifySoundLabel(kind)
}
