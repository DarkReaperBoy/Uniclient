package cores

import (
	"fmt"

	"github.com/gotd/td/telegram/auth"
	"github.com/gotd/td/tg"
)

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
