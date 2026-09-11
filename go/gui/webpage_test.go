package gui

import (
	"encoding/json"
	"testing"

	"uniclient/engine"
)

// Webpage previews (slice 117) — pure logic: Extra parsing (the same
// content_raw contract as poll/location bubbles), link detection for the
// composer toggle, card visibility. Engine-side no_webpage wiring is pinned
// in engine/webpage_test.go.

func wpMessage(extra map[string]interface{}) *engine.CachedMessage {
	env := struct {
		Extra map[string]interface{} `json:"extra"`
	}{Extra: extra}
	raw, _ := json.Marshal(env)
	return &engine.CachedMessage{
		AccountID:   "a",
		ChatID:      "c",
		MsgID:       "1",
		ContentText: "look at this",
		ContentRaw:  raw,
	}
}

func TestParseWebPage(t *testing.T) {
	m := wpMessage(map[string]interface{}{
		"wp_url":         "https://example.com/post",
		"wp_site_name":   "Example",
		"wp_title":       "A fine article",
		"wp_description": "All about example websites.",
		"wp_type":        "article",
		"wp_duration":    float64(42),
	})
	wp := parseWebPage(m)
	if wp == nil {
		t.Fatal("webpage not parsed")
	}
	if wp.URL != "https://example.com/post" || wp.SiteName != "Example" || wp.Title != "A fine article" {
		t.Fatalf("fields = %+v", wp)
	}
	if wp.Description != "All about example websites." || wp.Duration != 42 {
		t.Fatalf("desc/duration = %q/%d", wp.Description, wp.Duration)
	}

	// No extra → nil (plain text message).
	if parseWebPage(&engine.CachedMessage{ContentText: "hi"}) != nil {
		t.Fatal("plain message must not parse as webpage")
	}
	// wp_url alone is enough (other fields optional).
	m2 := wpMessage(map[string]interface{}{"wp_url": "https://x.org"})
	wp2 := parseWebPage(m2)
	if wp2 == nil || wp2.URL != "https://x.org" {
		t.Fatalf("url-only parse = %+v", wp2)
	}

	// Slice 130: the page photo's download coordinates ride along and
	// hasPhotoID gates the ensure path.
	m3 := wpMessage(map[string]interface{}{
		"wp_url":         "https://x.org/p",
		"wp_photo_id":    "9001",
		"wp_photo_extra": "279031:OQ==",
	})
	wp3 := parseWebPage(m3)
	if wp3 == nil || !wp3.hasPhotoID() || wp3.PhotoID != "9001" || wp3.PhotoExtra != "279031:OQ==" {
		t.Fatalf("photo coords parse = %+v", wp3)
	}
	m4 := wpMessage(map[string]interface{}{"wp_url": "https://x.org/q"})
	if wp4 := parseWebPage(m4); wp4 != nil && wp4.hasPhotoID() {
		t.Fatal("photo-less webpage reports a photo ID")
	}
}

func TestWebPageCardHostname(t *testing.T) {
	wp := &webPageData{URL: "https://example.com/post?x=1"}
	if got := wp.hostname(); got != "example.com" {
		t.Fatalf("hostname = %q", got)
	}
	wp2 := &webPageData{URL: "not a url"}
	if got := wp2.hostname(); got != "not a url" {
		t.Fatalf("fallback hostname = %q", got)
	}
}

func TestWebPageFallbackTitle(t *testing.T) {
	wp := &webPageData{URL: "https://example.com", SiteName: "Example"}
	if got := wp.displayTitle(); got != "Example" {
		t.Fatalf("site fallback = %q", got)
	}
	wp2 := &webPageData{URL: "https://example.com"}
	if got := wp2.displayTitle(); got != "example.com" {
		t.Fatalf("host fallback = %q", got)
	}
	wp3 := &webPageData{URL: "https://example.com", Title: "Real Title"}
	if got := wp3.displayTitle(); got != "Real Title" {
		t.Fatalf("title = %q", got)
	}
}

func TestComposedHasLink(t *testing.T) {
	cases := []struct {
		text string
		want bool
	}{
		{"no links here", false},
		{"", false},
		{"check https://example.com now", true},
		{"http://plain.org", true},
		{"see www.example.com/page", true},
		{"visit example.com directly", false}, // bare domain: Telegram requires scheme/www
		{"ftp://files.example.com", false},    // only http(s)/www count
	}
	for _, c := range cases {
		if got := composedHasLink(c.text); got != c.want {
			t.Errorf("composedHasLink(%q) = %v, want %v", c.text, got, c.want)
		}
	}
}
