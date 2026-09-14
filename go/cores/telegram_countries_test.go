package cores

// telegram_countries_test.go — slice 214 tests-first: the
// help.getCountriesList normalization (localized name fallback, hidden
// exclusion).

import (
	"testing"

	"github.com/gotd/td/tg"
)

func TestCountriesFromWire(t *testing.T) {
	res := &tg.HelpCountriesList{
		Countries: []tg.HelpCountry{
			{ISO2: "DE", DefaultName: "Deutschland"},
			{ISO2: "FR", DefaultName: "France", Name: "Frankreich"},
			{ISO2: "XX", DefaultName: "Hiddenland", Hidden: true},
		},
	}
	out := countriesFromWire(res.Countries)
	if len(out) != 2 {
		t.Fatalf("countries = %d, want 2 (hidden excluded)", len(out))
	}
	if out[0].ISO2 != "DE" || out[0].Name != "Deutschland" {
		t.Errorf("default-name fallback broken: %+v", out[0])
	}
	if out[1].ISO2 != "FR" || out[1].Name != "Frankreich" {
		t.Errorf("localized name lost: %+v", out[1])
	}
	if got := countriesFromWire(nil); len(got) != 0 {
		t.Errorf("nil list = %d", len(got))
	}
}
