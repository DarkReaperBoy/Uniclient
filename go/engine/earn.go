package engine

import (
	"fmt"
)

type StarsRevenueWithdrawer interface {
	WithdrawStarsRevenue(chatID string, ton bool, amount int64, password string) (string, error)
}

func (e *Engine) WithdrawStarsRevenue(accountID, chatID string, ton bool, amount int64, password string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return "", fmt.Errorf("account not connected: %s", accountID)
	}
	withdrawer, ok := acc.Core.(StarsRevenueWithdrawer)
	if !ok {
		return "", fmt.Errorf("platform does not support revenue withdrawal")
	}
	return withdrawer.WithdrawStarsRevenue(chatID, ton, amount, password)
}
