package app

import (
	"encoding/json"
	"sort"
)

type Account struct {
	ID          string `json:"id"`
	Platform    string `json:"platform"`
	DisplayName string `json:"display_name"`
	SortOrder   int    `json:"sort_order"`
	ConnState   int    `json:"conn_state"`
}

type EngineEventMsg struct {
	Data []byte
}

func (EngineEventMsg) isMsg() {}

const (
	engineEventAccountList = "account_list"

	AddAccountPrompt = "Add an account"
)

func (m Model) applyEngineEvent(data []byte) (Model, Cmd) {
	var env engineEnvelope
	if json.Unmarshal(data, &env) != nil {
		return m, nil
	}
	switch env.Type {
	case engineEventAccountList:
		return m.applyAccountList(env.Data)
	case engineEventChatSnapshot:
		return m.applyChatSnapshot(env)
	case engineEventChatUpdated:
		return m.applyChatUpdated(env)
	case engineEventMsgReceived:
		return m.applyMsgReceived(env)
	}
	return m, nil
}

type engineEnvelope struct {
	Type        string          `json:"type"`
	AccountID   string          `json:"account_id"`
	TimestampMs int64           `json:"timestamp_ms"`
	Data        json.RawMessage `json:"data"`
}

func (m Model) applyAccountList(data []byte) (Model, Cmd) {
	var accounts []Account
	if json.Unmarshal(data, &accounts) != nil {
		return m, nil
	}
	sort.Slice(accounts, func(i, j int) bool {
		if accounts[i].SortOrder != accounts[j].SortOrder {
			return accounts[i].SortOrder < accounts[j].SortOrder
		}
		return accounts[i].ID < accounts[j].ID
	})
	m.Accounts = accounts
	return m, nil
}
