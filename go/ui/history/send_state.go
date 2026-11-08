package history

import "uniclient/ui/icons"

func SendStateIcon(out, sending, unread bool) (icons.Icon, bool) {
	if !out {
		return icons.Icon{}, false
	}
	if sending {
		return icons.HistorySending, true
	}
	if unread {
		return icons.HistorySent, true
	}
	return icons.HistoryReceived, true
}
