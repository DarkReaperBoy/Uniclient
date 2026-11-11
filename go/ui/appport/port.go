package appport

import (
	"uniclient/engine"
	"uniclient/ui/app"
	"uniclient/ui/dialogs"
)

const searchGlobalPage = 50

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
	return wireMessages(msgs), true
}

func (p chatPort) MessagesBefore(accountID, chatID string, beforeMs int64, limit int) ([]app.WireMessage, bool) {
	if beforeMs <= 0 {
		return nil, true
	}
	msgs, err := p.eng.GetMessages(accountID, chatID, beforeMs, 0, limit)
	if err != nil {
		return nil, false
	}
	return wireMessages(msgs), true
}

func wireMessages(msgs []engine.CachedMessage) []app.WireMessage {
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
	return out
}

func (p chatPort) Send(accountID, chatID, text string) bool {
	_, err := p.eng.SendMessage(accountID, chatID, text, "", nil, false, 0, "", "", false, false, false, false, false)
	return err == nil
}

func (p chatPort) SearchGlobalChats(accountID, query string) ([]dialogs.Entry, bool) {
	chats, err := p.eng.SearchGlobalChats(accountID, query, searchGlobalPage)
	if err != nil {
		return nil, false
	}
	rows := make([]dialogs.Entry, 0, len(chats))
	for _, c := range chats {
		e := dialogs.Entry{
			Account:  c.AccountID,
			ChatID:   c.ChatID,
			Name:     c.Title,
			Username: c.Username,
			Preview:  globalRowPreview(c),
		}
		switch c.Type {
		case app.ChatKindGroup, app.ChatKindTopic:
			e.Group = true
		case app.ChatKindChannel:
			e.ChatType = dialogs.ChatChannel
		}
		rows = append(rows, e)
	}
	return rows, true
}

func globalRowPreview(c engine.ChatInfo) string {
	if c.Username != "" {
		return "@" + c.Username
	}
	return "ID: " + c.ChatID
}
