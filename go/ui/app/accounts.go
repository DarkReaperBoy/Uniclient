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
	var env struct {
		Type string          `json:"type"`
		Data json.RawMessage `json:"data"`
	}
	if json.Unmarshal(data, &env) != nil || env.Type != engineEventAccountList {
		return m, nil
	}
	var accounts []Account
	if json.Unmarshal(env.Data, &accounts) != nil {
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
