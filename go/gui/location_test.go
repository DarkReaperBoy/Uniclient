package gui

import (
	"encoding/json"
	"testing"

	"uniclient/engine"
)

// geo/content parse helpers (slice 56): location & contact payloads read
// from content_raw Extra; nil paths and formatting locked here.
func geoRaw(t *testing.T, extra map[string]interface{}) []byte {
	t.Helper()
	raw, err := json.Marshal(map[string]interface{}{"extra": extra})
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func TestParseGeoMessage(t *testing.T) {
	m := &engine.CachedMessage{ContentRaw: geoRaw(t, map[string]interface{}{
		"geo_lat": 41.0082, "geo_long": 28.9784,
	})}
	g := parseGeoMessage(m)
	if g == nil || g.Lat != 41.0082 || g.Long != 28.9784 || g.Live {
		t.Fatalf("geo = %+v", g)
	}
	if got, want := g.coordLabel(), "41.008200, 28.978400"; got != want {
		t.Errorf("coordLabel = %q, want %q", got, want)
	}
	if got, want := g.mapsURL(), "https://maps.google.com/?q=41.008200,28.978400"; got != want {
		t.Errorf("mapsURL = %q, want %q", got, want)
	}

	live := &engine.CachedMessage{ContentRaw: geoRaw(t, map[string]interface{}{
		"geo_lat": 1.5, "geo_long": -2.25, "geo_live": true, "geo_period": float64(900),
	})}
	g = parseGeoMessage(live)
	if g == nil || !g.Live || g.Period != 900 {
		t.Fatalf("live geo = %+v", g)
	}
	if got := liveBadgeText(g); got != "live · 15m" {
		t.Errorf("liveBadgeText = %q", got)
	}
	if got := liveBadgeText(nil); got != "" {
		t.Errorf("nil badge = %q", got)
	}

	if parseGeoMessage(&engine.CachedMessage{}) != nil {
		t.Error("no content = nil")
	}
	if parseGeoMessage(&engine.CachedMessage{ContentRaw: []byte(`{"extra":{"other":1}}`)}) != nil {
		t.Error("no geo keys = nil")
	}
	if parseGeoMessage(&engine.CachedMessage{ContentRaw: []byte(`{"extra":{"geo_lat":"x"}}`)}) != nil {
		t.Error("non-numeric geo = nil")
	}
}

func TestParseContactMessage(t *testing.T) {
	m := &engine.CachedMessage{ContentRaw: geoRaw(t, map[string]interface{}{
		"contact_phone": "+15550100", "contact_first_name": "Ada", "contact_last_name": "Lovelace", "contact_user_id": "42",
	})}
	c := parseContactMessage(m)
	if c == nil || c.Phone != "+15550100" || c.UserID != "42" {
		t.Fatalf("contact = %+v", c)
	}
	if got, want := c.fullName(), "Ada Lovelace"; got != want {
		t.Errorf("fullName = %q, want %q", got, want)
	}
	if parseContactMessage(&engine.CachedMessage{}) != nil {
		t.Error("no content = nil")
	}
}

func TestSplitContactName(t *testing.T) {
	first, last := splitContactName("Ada Lovelace")
	if first != "Ada" || last != "Lovelace" {
		t.Errorf("split = %q %q", first, last)
	}
	first, last = splitContactName("Cher")
	if first != "Cher" || last != "" {
		t.Errorf("single = %q %q", first, last)
	}
	first, last = splitContactName("  Grace  Murray  Hopper ")
	if first != "Grace" || last != "Murray Hopper" {
		t.Errorf("multi = %q %q", first, last)
	}
	if blankFirst, blankLast := splitContactName("   "); blankFirst != "" || blankLast != "" {
		t.Error("blank = empty pair")
	}
}

func TestParseCoords(t *testing.T) {
	lat, lon, err := parseCoords(" 41.0082 ", "-28.9784")
	if err != nil || lat != 41.0082 || lon != -28.9784 {
		t.Fatalf("coords = %v %v %v", lat, lon, err)
	}
	if _, _, err := parseCoords("abc", "1"); err == nil || err.Error() != "latitude" {
		t.Errorf("lat err = %v", err)
	}
	if _, _, err := parseCoords("1", "x"); err == nil || err.Error() != "longitude" {
		t.Errorf("lon err = %v", err)
	}
}
