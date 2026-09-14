package engine

// giveaways.go — slice 212: typed giveaway surface — options fetch,
// balance-funded creation and prepaid launch, each gated on the core's
// optional interface with honest errors on plain cores. Replaces the
// pre-slice-212 map-typed family (LaunchRandomGiveaway,
// LaunchCreditsGiveaway, GetGiveawayConfig, AwardPremiumGiveaway — dead
// surface, deleted).

import (
	"fmt"

	"uniclient/cores"
)

// StarsGiveawayOptionsFetcher lists the giveaway prize options
// (payments.getStarsGiveawayOptions).
type StarsGiveawayOptionsFetcher interface {
	GetStarsGiveawayOptions() ([]cores.StarsGiveawayOptionInfo, error)
}

// StarsGiveawayCreator funds a giveaway from the account's star balance.
type StarsGiveawayCreator interface {
	CreateStarsGiveaway(chatID string, opt cores.StarsGiveawayOptionInfo, p cores.GiveawayParams) error
}

// PrepaidGiveawayLauncher launches an already-paid giveaway
// (payments.launchPrepaidGiveaway).
type PrepaidGiveawayLauncher interface {
	LaunchPrepaidGiveaway(chatID string, giveawayID int64, credits int64, months int, p cores.GiveawayParams) error
}

// CountriesListFetcher lists countries (help.getCountriesList).
type CountriesListFetcher interface {
	GetCountriesList(langCode string) ([]cores.CountryInfo, error)
}

// GetCountriesList returns the country rows for the giveaway picker.
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

// GetStarsGiveawayOptions returns the prize options for the account.
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

// CreateStarsGiveaway funds a stars giveaway for the channel from the
// account's star balance.
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

// LaunchPrepaidGiveaway launches an already-paid giveaway entry
// (credits > 0 = prepaid stars, months > 0 = prepaid premium).
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
