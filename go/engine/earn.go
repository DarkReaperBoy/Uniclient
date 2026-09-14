package engine

// earn.go — slice 213: stars-revenue withdrawal passthrough (the stats
// Earn tab's Withdraw button; the URL opens in the browser).

import (
	"fmt"
)

// StarsRevenueWithdrawer requests the withdrawal URL
// (payments.getStarsRevenueWithdrawalURL).
type StarsRevenueWithdrawer interface {
	WithdrawStarsRevenue(chatID string, ton bool, amount int64, password string) (string, error)
}

// WithdrawStarsRevenue requests the withdrawal URL for the channel's
// TON revenue (ton=true) or a bot's star balance (amount nanostars).
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
