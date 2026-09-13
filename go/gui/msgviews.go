package gui

// Channel-post views ticker (slice 187): an open channel chat refreshes
// its view/forward counters once on open, then every
// engine.ViewsRefreshInterval seconds while it stays open (tdesktop's
// refreshChannelViews cadence). Counters merge into the open window in
// place — no wholesale reload that could race concurrent message events.

import (
	"log"
	"time"

	"uniclient/engine"
)

// syncViewsRefresh starts/retargets/stops the views ticker for the
// currently selected chat (channels only).
func (a *App) syncViewsRefresh() {
	a.mu.Lock()
	selected := a.selected
	var target *chatKey
	if selected != nil {
		for _, c := range a.chats {
			if c.AccountID == selected.AccountID && c.ChatID == selected.ChatID &&
				c.Type == engine.ChatTypeChanVal && !c.IsForum {
				k := *selected
				target = &k
				break
			}
		}
	}
	already := a.viewsPollFor
	a.viewsPollFor = target
	a.mu.Unlock()
	if target == nil {
		return
	}
	if already != nil && *already == *target {
		return // loop is already watching this chat
	}
	go func(k chatKey) {
		a.pollViewsOnce(k)
		t := time.NewTicker(engine.ViewsRefreshInterval * time.Second)
		defer t.Stop()
		for range t.C {
			a.mu.Lock()
			cur := a.selected
			forChat := a.viewsPollFor
			a.mu.Unlock()
			if cur == nil || forChat == nil || *cur != k || *forChat != k {
				return
			}
			a.pollViewsOnce(k)
		}
	}(*target)
}

// pollViewsOnce runs one refresh pass and merges the counters into the
// open window's rows by message id.
func (a *App) pollViewsOnce(k chatKey) {
	changed, err := a.eng.RefreshMessageViews(k.AccountID, k.ChatID)
	if err != nil {
		// Quiet: offline channels keep their last cached counters.
		log.Printf("gui: views refresh (%s/%s): %v", k.AccountID, k.ChatID, err)
		return
	}
	if changed == 0 {
		return
	}
	msgs, err := a.eng.GetMessages(k.AccountID, k.ChatID, 0, 0, 200)
	if err != nil {
		return
	}
	byID := make(map[string][2]int, len(msgs))
	for _, m := range msgs {
		byID[m.MsgID] = [2]int{m.Views, m.Forwards}
	}
	a.mu.Lock()
	if a.msgFor != nil && *a.msgFor == k {
		for i := range a.messages {
			if vf, ok := byID[a.messages[i].MsgID]; ok {
				a.messages[i].Views = vf[0]
				a.messages[i].Forwards = vf[1]
			}
		}
	}
	a.mu.Unlock()
	a.invalidate()
}
