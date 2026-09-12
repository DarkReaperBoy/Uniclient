package engine

import (
	"encoding/json"
	"fmt"

	"uniclient/cores"
)

type premiumFeaturesGetter interface {
	GetPremiumFeatures() ([]string, error)
}

type premiumPromoGetter interface {
	GetPremiumPromo() (cores.PremiumPromo, error)
}

type premiumSubscriptionOpener interface {
	OpenPremiumSubscription(ref string) error
}

type starsPurchaseOpener interface {
	OpenStarsPurchase() error
}

type starsTransactionsGetter interface {
	GetStarsTransactions() ([]map[string]interface{}, error)
}

type myStarsGetter interface {
	GetMyStars(offset, filter string) (cores.StarsStatus, error)
}

type tonBalanceGetter interface {
	GetTonBalance() (string, error)
}

type businessInfoGetter interface {
	GetBusinessInfo() (map[string]interface{}, error)
}

type businessFeatureGetter interface {
	GetBusinessFeature(feature string) (map[string]interface{}, error)
}

type businessFeatureSetter interface {
	SetBusinessFeature(feature string, data map[string]interface{}) error
}

type businessChatLinkCreator interface {
	CreateBusinessChatLink() (string, error)
}

type emojiStatusSetter interface {
	SetEmojiStatus(documentID int64, expiresIn int) error
}

type emojiStatusClearer interface {
	ClearEmojiStatus() error
}

type quickReplyDeleter interface {
	DeleteQuickReply(shortcutID int) error
}

type businessLinkDeleter interface {
	DeleteBusinessLink(slug string) error
}

type timezonesGetter interface {
	GetTimezones() ([]cores.TimezoneInfo, error)
}

type quickRepliesGetter interface {
	GetQuickReplies() ([]cores.QuickReplyInfo, error)
}

type quickReplyCreator interface {
	CreateQuickReply(name, text string) (int, error)
}

type quickReplyRenamer interface {
	RenameQuickReply(id int, name string) error
}

// GetMyStars returns the account's own Stars balance + transaction
// history; nil status for cores without stars (the GUI hides honestly).
func (e *Engine) GetMyStars(accountID, offset, filter string) (*cores.StarsStatus, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	g, ok := acc.Core.(myStarsGetter)
	if !ok {
		return nil, nil
	}
	st, err := g.GetMyStars(offset, filter)
	if err != nil {
		return nil, err
	}
	return &st, nil
}

// GetPremiumPromo returns the account's premium promotional state
// (subscription status + purchasable plans); nil state for cores
// without premium support (the GUI hides the section honestly).
func (e *Engine) GetPremiumPromo(accountID string) (*cores.PremiumPromo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	g, ok := acc.Core.(premiumPromoGetter)
	if !ok {
		return nil, nil
	}
	promo, err := g.GetPremiumPromo()
	if err != nil {
		return nil, err
	}
	return &promo, nil
}

func (e *Engine) GetPremiumFeatures(accountID string) ([]string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	g, ok := acc.Core.(premiumFeaturesGetter)
	if !ok {
		return nil, nil
	}
	return g.GetPremiumFeatures()
}

func (e *Engine) OpenPremiumSubscription(accountID, ref string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	o, ok := acc.Core.(premiumSubscriptionOpener)
	if !ok {
		return fmt.Errorf("core does not support premium subscription")
	}
	return o.OpenPremiumSubscription(ref)
}

func (e *Engine) OpenStarsPurchase(accountID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	o, ok := acc.Core.(starsPurchaseOpener)
	if !ok {
		return fmt.Errorf("core does not support stars purchase")
	}
	return o.OpenStarsPurchase()
}

func (e *Engine) GetStarsTransactions(accountID string) ([]byte, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	g, ok := acc.Core.(starsTransactionsGetter)
	if !ok {
		return json.Marshal(map[string]interface{}{"transactions": []interface{}{}})
	}
	txns, err := g.GetStarsTransactions()
	if err != nil {
		return nil, err
	}
	return json.Marshal(map[string]interface{}{"transactions": txns})
}

func (e *Engine) GetTonBalance(accountID string) ([]byte, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	g, ok := acc.Core.(tonBalanceGetter)
	if !ok {
		return json.Marshal(map[string]interface{}{"balance": ""})
	}
	balance, err := g.GetTonBalance()
	if err != nil {
		return json.Marshal(map[string]interface{}{"balance": ""})
	}
	return json.Marshal(map[string]interface{}{"balance": balance})
}

func (e *Engine) GetBusinessInfo(accountID string) ([]byte, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	g, ok := acc.Core.(businessInfoGetter)
	if !ok {
		return json.Marshal(map[string]interface{}{})
	}
	info, err := g.GetBusinessInfo()
	if err != nil {
		return nil, err
	}
	return json.Marshal(info)
}

func (e *Engine) GetBusinessFeature(accountID, feature string) ([]byte, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	g, ok := acc.Core.(businessFeatureGetter)
	if !ok {
		return json.Marshal(map[string]interface{}{})
	}
	data, err := g.GetBusinessFeature(feature)
	if err != nil {
		return nil, err
	}
	return json.Marshal(data)
}

func (e *Engine) SetBusinessFeature(accountID, feature string, data map[string]interface{}) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	s, ok := acc.Core.(businessFeatureSetter)
	if !ok {
		return fmt.Errorf("core does not support business features")
	}
	return s.SetBusinessFeature(feature, data)
}

func (e *Engine) CreateBusinessChatLink(accountID string) ([]byte, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	c, ok := acc.Core.(businessChatLinkCreator)
	if !ok {
		return nil, fmt.Errorf("core does not support business chat links")
	}
	link, err := c.CreateBusinessChatLink()
	if err != nil {
		return nil, err
	}
	return json.Marshal(map[string]interface{}{"link": link})
}

func (e *Engine) SetEmojiStatus(accountID string, documentID int64, expiresIn int) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	s, ok := acc.Core.(emojiStatusSetter)
	if !ok {
		return fmt.Errorf("core does not support emoji status")
	}
	return s.SetEmojiStatus(documentID, expiresIn)
}

func (e *Engine) ClearEmojiStatus(accountID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	c, ok := acc.Core.(emojiStatusClearer)
	if !ok {
		return fmt.Errorf("core does not support emoji status")
	}
	return c.ClearEmojiStatus()
}

func (e *Engine) DeleteQuickReplyShortcut(accountID string, shortcutID int) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	d, ok := acc.Core.(quickReplyDeleter)
	if !ok {
		return fmt.Errorf("core does not support quick reply deletion")
	}
	return d.DeleteQuickReply(shortcutID)
}

func (e *Engine) DeleteBusinessChatLink(accountID, slug string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	d, ok := acc.Core.(businessLinkDeleter)
	if !ok {
		return fmt.Errorf("core does not support business link deletion")
	}
	return d.DeleteBusinessLink(slug)
}

// GetTimezones returns the server timezone list for the business
// opening-hours picker; nil for cores without it (the editor falls back
// to a plain ID field, honest scope).
func (e *Engine) GetTimezones(accountID string) ([]cores.TimezoneInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	g, ok := acc.Core.(timezonesGetter)
	if !ok {
		return nil, nil
	}
	return g.GetTimezones()
}

// GetQuickReplies lists the account's quick reply shortcuts; nil for
// cores without them (the section hides honestly).
func (e *Engine) GetQuickReplies(accountID string) ([]cores.QuickReplyInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	g, ok := acc.Core.(quickRepliesGetter)
	if !ok {
		return nil, nil
	}
	return g.GetQuickReplies()
}

// CreateQuickReply creates a shortcut with its first message, returning
// the new shortcut ID.
func (e *Engine) CreateQuickReply(accountID, name, text string) (int, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return 0, fmt.Errorf("account not found: %s", accountID)
	}
	c, ok := acc.Core.(quickReplyCreator)
	if !ok {
		return 0, fmt.Errorf("core does not support quick replies")
	}
	return c.CreateQuickReply(name, text)
}

// RenameQuickReply renames a quick reply shortcut.
func (e *Engine) RenameQuickReply(accountID string, id int, name string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	r, ok := acc.Core.(quickReplyRenamer)
	if !ok {
		return fmt.Errorf("core does not support quick replies")
	}
	return r.RenameQuickReply(id, name)
}
