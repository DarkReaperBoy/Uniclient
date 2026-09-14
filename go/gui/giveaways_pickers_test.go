package gui

// giveaways_pickers_test.go — slice 214 tests: pure helpers for the
// giveaway country + channel pickers (labels, search filter, candidate
// filtering, selection labels).

import (
	"testing"

	"uniclient/cores"
	"uniclient/engine"
)

func TestCountryLabel(t *testing.T) {
	if got := countryLabel(cores.CountryInfo{ISO2: "DE", Name: "Deutschland"}); got != "Deutschland" {
		t.Errorf("label = %q", got)
	}
	// Localized name missing → default name.
	if got := countryLabel(cores.CountryInfo{ISO2: "FR", Name: "France"}); got != "France" {
		t.Errorf("label = %q", got)
	}
}

func TestCountryMatches(t *testing.T) {
	list := []cores.CountryInfo{
		{ISO2: "DE", Name: "Deutschland"},
		{ISO2: "FR", Name: "France"},
		{ISO2: "US", Name: "United States"},
	}
	if got := countryMatches(list, "deutsch"); len(got) != 1 || got[0].ISO2 != "DE" {
		t.Errorf("name search = %+v", got)
	}
	if got := countryMatches(list, "united"); len(got) != 1 || got[0].ISO2 != "US" {
		t.Errorf("multi-word search = %+v", got)
	}
	if got := countryMatches(list, "D"); len(got) != 1 || got[0].ISO2 != "DE" {
		t.Errorf("case-insensitive = %+v", got)
	}
	if got := countryMatches(list, "us"); len(got) != 1 || got[0].ISO2 != "US" {
		t.Errorf("iso search = %+v", got)
	}
	if got := countryMatches(list, ""); len(got) != len(list) {
		t.Errorf("empty query must keep all: %d", len(got))
	}
	if got := countryMatches(list, "zzz"); len(got) != 0 {
		t.Errorf("no-match kept rows: %d", len(got))
	}
}

func TestGiveawayCountryLabel(t *testing.T) {
	if got := giveawayCountryLabel(nil); got != "All countries" {
		t.Errorf("empty selection = %q", got)
	}
	if got := giveawayCountryLabel(map[string]bool{"DE": true, "FR": true}); got != "2 countries selected" {
		t.Errorf("selection label = %q", got)
	}
	if got := giveawayCountryLabel(map[string]bool{"DE": true}); got != "1 country selected" {
		t.Errorf("single label = %q", got)
	}
}

func TestGiveawayChannelCandidates(t *testing.T) {
	chats := []engine.ChatInfo{
		{AccountID: "a", ChatID: "1", Type: engine.ChatTypeChanVal, Title: "News"},
		{AccountID: "a", ChatID: "2", Type: engine.ChatTypeGroupVal, Title: "Group"},
		{AccountID: "b", ChatID: "3", Type: engine.ChatTypeChanVal, Title: "Other acct"},
		{AccountID: "a", ChatID: "4", Type: engine.ChatTypeDMVal, Title: "DM"},
	}
	// Only same-account channels, excluding the giveaway channel itself.
	got := giveawayChannelCandidates(chats, "a", "1")
	if len(got) != 0 {
		t.Fatalf("self-channel must be excluded: %+v", got)
	}
	got2 := giveawayChannelCandidates(chats, "a", "9")
	if len(got2) != 1 || got2[0].ChatID != "1" {
		t.Errorf("candidates = %+v", got2)
	}
	if got3 := giveawayChannelCandidates(nil, "a", "9"); len(got3) != 0 {
		t.Errorf("nil chats = %d", len(got3))
	}
}

func TestGiveawayChannelsLabel(t *testing.T) {
	if got := giveawayChannelsLabel(nil); got != "This channel only" {
		t.Errorf("empty = %q", got)
	}
	if got := giveawayChannelsLabel(map[string]bool{"1": true}); got != "1 additional channel" {
		t.Errorf("single = %q", got)
	}
	if got := giveawayChannelsLabel(map[string]bool{"1": true, "2": true}); got != "2 additional channels" {
		t.Errorf("multi = %q", got)
	}
}
