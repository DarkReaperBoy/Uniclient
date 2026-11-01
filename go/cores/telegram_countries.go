package cores

import (
	"fmt"

	"github.com/gotd/td/tg"
)

func countriesFromWire(list []tg.HelpCountry) []CountryInfo {
	out := make([]CountryInfo, 0, len(list))
	for _, c := range list {
		if c.Hidden {
			continue
		}
		name := c.Name
		if name == "" {
			name = c.DefaultName
		}
		out = append(out, CountryInfo{ISO2: c.ISO2, Name: name})
	}
	return out
}

func (t *TelegramCore) GetCountriesList(langCode string) ([]CountryInfo, error) {
	api, ctx, err := t.withAPI()
	if err != nil {
		return nil, err
	}
	res, err := api.HelpGetCountriesList(ctx, &tg.HelpGetCountriesListRequest{
		LangCode: langCode,
	})
	if err != nil {
		return nil, fmt.Errorf("get countries list: %w", err)
	}
	switch r := res.(type) {
	case *tg.HelpCountriesList:
		return countriesFromWire(r.Countries), nil
	case *tg.HelpCountriesListNotModified:
		return nil, fmt.Errorf("countries list not modified (hash-cached call without a cached list)")
	default:
		return nil, fmt.Errorf("unexpected countries result %T", res)
	}
}
