package app

import (
	"strings"

	"uniclient/ui/dialogs"
	"uniclient/ui/tokens"
)

type GlobalSearchState struct {
	TypedAt  int
	Fired    bool
	Resolved bool
	Query    string
	Rows     []dialogs.Entry
}

func (m Model) SearchGlobalPending() bool {
	return m.globalSearchArmed() && !m.GlobalSearch.Fired
}

func (m Model) SearchGlobalLoading() bool {
	return m.globalSearchArmed() && !m.GlobalSearch.Resolved
}

func (m Model) globalSearchArmed() bool {
	if len(m.Accounts) == 0 {
		return false
	}
	text := strings.TrimSpace(m.Search.Text)
	return text != "" && text != "@"
}

func (m *Model) resetSearchGlobalOnText(now int) {
	if m.globalSearchArmed() {
		m.GlobalSearch.TypedAt = now
		m.GlobalSearch.Fired = false
		m.GlobalSearch.Resolved = false
		return
	}
	m.GlobalSearch = GlobalSearchState{}
}

func (m *Model) searchGlobalTick(now int) Cmd {
	if !m.SearchGlobalPending() || now-m.GlobalSearch.TypedAt < tokens.SearchRequestDelayMs {
		return nil
	}
	m.GlobalSearch.Fired = true
	return m.searchGlobalCmd()
}

func (m *Model) searchGlobalCmd() Cmd {
	if m.port == nil {
		return nil
	}
	port, accounts, query := m.port, m.accountIDs(), strings.TrimSpace(m.Search.Text)
	if len(accounts) == 0 {
		return nil
	}
	return func() Msg {
		rows := make([]dialogs.Entry, 0, len(accounts))
		for _, id := range accounts {
			if found, ok := port.SearchGlobalChats(id, query); ok {
				rows = append(rows, found...)
			}
		}
		return SearchGlobalLoaded{Query: query, Rows: rows}
	}
}

func (m *Model) applySearchGlobalLoaded(msg SearchGlobalLoaded) (Model, Cmd) {
	if msg.Query != strings.TrimSpace(m.Search.Text) {
		return *m, nil
	}
	m.GlobalSearch.Resolved = true
	m.GlobalSearch.Query = msg.Query
	m.GlobalSearch.Rows = msg.Rows
	m.reprojectDialogRows()
	return *m, nil
}

func (m Model) accountIDs() []string {
	ids := make([]string, 0, len(m.Accounts))
	for _, acc := range m.Accounts {
		ids = append(ids, acc.ID)
	}
	return ids
}
