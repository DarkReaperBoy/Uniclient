package gui

import (
	"log"
	"time"

	"uniclient/engine"
)

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
		return
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

func (a *App) pollViewsOnce(k chatKey) {
	changed, err := a.eng.RefreshMessageViews(k.AccountID, k.ChatID)
	if err != nil {
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
