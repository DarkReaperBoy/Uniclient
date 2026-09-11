package gui

// traysnap.go — slice 137: the pure state projection the system tray
// renders from (per-account unread counts, the ghost/streamer toggles).
// Cross-platform and unit-tested; the platform tray controller (tray.go)
// consumes it.

import (
	"uniclient/engine"
)

// trayAccount is one account row in the tray menu.
type trayAccount struct {
	ID     string
	Name   string
	Unread int
}

// traySnapshot is everything the tray displays at a moment.
type traySnapshot struct {
	Accounts    []trayAccount
	TotalUnread int
	Ghost       bool
	Streamer    bool
}

// traySnapshotFrom projects app state into the tray snapshot. Pure.
func traySnapshotFrom(accounts []engine.AccountInfo, chats []engine.ChatInfo, cfg cfgSnapshot) traySnapshot {
	unread := make(map[string]int, len(accounts))
	total := 0
	for i := range chats {
		if chats[i].UnreadCount > 0 {
			unread[chats[i].AccountID] += chats[i].UnreadCount
			total += chats[i].UnreadCount
		}
	}
	rows := make([]trayAccount, 0, len(accounts))
	for _, acc := range accounts {
		rows = append(rows, trayAccount{
			ID:     acc.ID,
			Name:   trayAccountDisplayName(acc),
			Unread: unread[acc.ID],
		})
	}
	return traySnapshot{
		Accounts:    rows,
		TotalUnread: total,
		Ghost:       ghostAllOn(cfg),
		Streamer:    cfg.Streamer,
	}
}

// trayAccountDisplayName renders an account's menu label basis: display
// name, else @username, else phone, else the platform title. Pure.
func trayAccountDisplayName(acc engine.AccountInfo) string {
	if acc.DisplayName != "" {
		return acc.DisplayName
	}
	if acc.Username != "" {
		return "@" + acc.Username
	}
	if acc.Phone != "" {
		return acc.Phone
	}
	return platformTitle(acc.Platform)
}

// trayAccountLabel formats one account row's label with its unread count.
// Pure.
func trayAccountLabel(name string, unread int) string {
	if unread <= 0 {
		return name
	}
	return name + " (" + trayCountLabel(unread) + ")"
}
