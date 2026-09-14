package cores

// telegram_earn.go — slice 213: stars-revenue withdrawal
// (payments.getStarsRevenueWithdrawalURL, tdesktop
// api_earn.cpp HandleWithdrawalButton): channel TON revenue or bot stars
// balance, gated by the account's 2FA password (SRP), returning the
// withdrawal URL the GUI opens in the browser.

import (
	"fmt"

	"github.com/gotd/td/telegram/auth"
	"github.com/gotd/td/tg"
)

// withdrawStarsRevenueRequest builds the withdrawal request. TON mode
// (channel revenue) sets f_ton and no amount; stars mode (bot balance)
// sets f_amount in nanostars. Pure — unit-tested.
func withdrawStarsRevenueRequest(peer tg.InputPeerClass, ton bool, amount int64, srp tg.InputCheckPasswordSRPClass) *tg.PaymentsGetStarsRevenueWithdrawalURLRequest {
	req := &tg.PaymentsGetStarsRevenueWithdrawalURLRequest{
		Peer:     peer,
		Password: srp,
	}
	if ton {
		req.SetTon(true)
	} else {
		req.SetAmount(amount)
	}
	return req
}

// WithdrawStarsRevenue requests the withdrawal URL. ton=true withdraws
// the channel's TON ad/subscriber revenue (full balance, amount
// ignored); ton=false withdraws `amount` nanostars from a bot's star
// balance. password is the account's 2FA cloud password — empty means
// no password attempt (the server rejects with PASSWORD_MISSING when
// one is set; the GUI surfaces that honestly).
func (t *TelegramCore) WithdrawStarsRevenue(chatID string, ton bool, amount int64, password string) (string, error) {
	api, ctx, err := t.withAPI()
	if err != nil {
		return "", err
	}
	inputPeer, unlock, perr := t.withPeer(chatID)
	if perr != nil {
		return "", fmt.Errorf("resolve peer: %w", perr)
	}
	defer unlock()

	var srp tg.InputCheckPasswordSRPClass = &tg.InputCheckPasswordEmpty{}
	if password != "" {
		pw, err := api.AccountGetPassword(ctx)
		if err != nil {
			return "", err
		}
		if !pw.HasPassword {
			return "", fmt.Errorf("no 2FA password is set on this account")
		}
		srp, err = auth.PasswordHash([]byte(password), pw.SRPID, pw.SRPB, pw.SecureRandom, pw.CurrentAlgo)
		if err != nil {
			return "", fmt.Errorf("SRP computation failed: %w", err)
		}
	}

	res, err := api.PaymentsGetStarsRevenueWithdrawalURL(ctx,
		withdrawStarsRevenueRequest(inputPeer, ton, amount, srp))
	if err != nil {
		return "", err
	}
	return res.URL, nil
}
