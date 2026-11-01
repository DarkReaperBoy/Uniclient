package engine

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
