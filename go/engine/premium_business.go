package engine

import (
	"encoding/json"
	"fmt"
)

type premiumFeaturesGetter interface {
	GetPremiumFeatures() ([]string, error)
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
