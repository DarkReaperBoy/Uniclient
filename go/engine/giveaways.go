package engine

import (
	"fmt"

	"uniclient/cores"
)

type StarsGiveawayOptionsFetcher interface {
	GetStarsGiveawayOptions() ([]cores.StarsGiveawayOptionInfo, error)
}

type StarsGiveawayCreator interface {
	CreateStarsGiveaway(chatID string, opt cores.StarsGiveawayOptionInfo, p cores.GiveawayParams) error
}

type PrepaidGiveawayLauncher interface {
	LaunchPrepaidGiveaway(chatID string, giveawayID int64, credits int64, months int, p cores.GiveawayParams) error
}

type CountriesListFetcher interface {
	GetCountriesList(langCode string) ([]cores.CountryInfo, error)
}

func (e *Engine) GetCountriesList(accountID, langCode string) ([]cores.CountryInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(CountriesListFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support the country list")
	}
	return fetcher.GetCountriesList(langCode)
}

func (e *Engine) GetStarsGiveawayOptions(accountID string) ([]cores.StarsGiveawayOptionInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(StarsGiveawayOptionsFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support stars giveaways")
	}
	return fetcher.GetStarsGiveawayOptions()
}

func (e *Engine) CreateStarsGiveaway(accountID, chatID string, opt cores.StarsGiveawayOptionInfo, p cores.GiveawayParams) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	creator, ok := acc.Core.(StarsGiveawayCreator)
	if !ok {
		return fmt.Errorf("platform does not support stars giveaways")
	}
	return creator.CreateStarsGiveaway(chatID, opt, p)
}

func (e *Engine) LaunchPrepaidGiveaway(accountID, chatID string, giveawayID int64, credits int64, months int, p cores.GiveawayParams) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	launcher, ok := acc.Core.(PrepaidGiveawayLauncher)
	if !ok {
		return fmt.Errorf("platform does not support prepaid giveaways")
	}
	return launcher.LaunchPrepaidGiveaway(chatID, giveawayID, credits, months, p)
}
