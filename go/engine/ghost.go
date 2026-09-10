package engine

// ghostAutoRead sends a read receipt for the given message if ghost mode
// blocks reads but markReadAfterAction is enabled (the "read on interact"
// pattern from AyuGram §51.10 — auto-read when user reacts or votes).
func (e *Engine) ghostAutoRead(accountID, chatID, msgID string) {
	g := e.GhostFor(accountID)
	if g.SendReadReceipts || !g.MarkReadAfterAction {
		return
	}
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return
	}
	acc.Core.MarkAsRead(chatID, msgID)
}
