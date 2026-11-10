package appport

import (
	"uniclient/engine"
	"uniclient/ui/app"
)

type chatPort struct {
	eng *engine.Engine
}

func For(eng *engine.Engine) app.ChatPort {
	return chatPort{eng: eng}
}

func (p chatPort) Messages(accountID, chatID string, limit int) ([]app.WireMessage, bool) {
	msgs, err := p.eng.GetMessages(accountID, chatID, 0, 0, limit)
	if err != nil {
		return nil, false
	}
	out := make([]app.WireMessage, 0, len(msgs))
	for _, cm := range msgs {
		out = append(out, app.WireMessage{
			ID:          cm.MsgID,
			SenderID:    cm.SenderID,
			SenderName:  cm.SenderName,
			Text:        cm.ContentText,
			TimestampMs: cm.Timestamp,
			Status:      cm.Status,
			Out:         cm.IsOutgoing,
			Service:     cm.IsService,
		})
	}
	for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
		out[i], out[j] = out[j], out[i]
	}
	return out, true
}

func (p chatPort) Send(accountID, chatID, text string) bool {
	_, err := p.eng.SendMessage(accountID, chatID, text, "", nil, false, 0, "", "", false, false, false, false, false)
	return err == nil
}
