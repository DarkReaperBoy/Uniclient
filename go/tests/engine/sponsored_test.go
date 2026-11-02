package tests

import (
	"strings"
	"testing"
	"time"

	"uniclient/cores"
)

type sponsoredStub struct {
	cores.StubCore
	fetches  int
	views    []string
	clicks   []string
	reports  int
	toggled  []bool
	response []cores.SponsoredMessageInfo
}

func (s *sponsoredStub) GetSponsoredMessages(chatID string) ([]cores.SponsoredMessageInfo, int, error) {
	s.fetches++
	return s.response, 20, nil
}

func (s *sponsoredStub) ViewSponsoredMessage(randomID string) error {
	s.views = append(s.views, randomID)
	return nil
}

func (s *sponsoredStub) ClickSponsoredMessage(randomID string, media, fullscreen bool) error {
	s.clicks = append(s.clicks, randomID)
	return nil
}

func (s *sponsoredStub) ReportSponsoredMessage(randomID, option string) (string, []cores.SponsoredReportOption, error) {
	s.reports++
	if option == "" {
		return "What's wrong?", []cores.SponsoredReportOption{
			{Text: "Spam", Option: "01"},
			{Text: "Misleading", Option: "02"},
		}, nil
	}
	return "", nil, nil
}

func (s *sponsoredStub) ToggleSponsoredMessages(enabled bool) error {
	s.toggled = append(s.toggled, enabled)
	return nil
}

func TestGetSponsoredMessagesCachesFiveMinutes(t *testing.T) {
	e := newTestEngine(t)
	stub := &sponsoredStub{response: []cores.SponsoredMessageInfo{
		{RandomID: "aabb", Title: "Ad", Message: "buy", ButtonText: "Open"},
	}}
	if err := e.AttachAccount("tg", "telegram", stub); err != nil {
		t.Fatal(err)
	}
	if err := e.AttachAccount("irc", "irc", plainStub{}); err != nil {
		t.Fatal(err)
	}

	items, posts, err := e.GetSponsoredMessages("tg", "-1001234")
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if len(items) != 1 || items[0].RandomID != "aabb" || posts != 20 {
		t.Fatalf("items/posts = %+v/%d", items, posts)
	}
	if stub.fetches != 1 {
		t.Fatalf("fetches = %d, want 1", stub.fetches)
	}

	if _, _, err := e.GetSponsoredMessages("tg", "-1001234"); err != nil {
		t.Fatalf("cached get: %v", err)
	}
	if stub.fetches != 1 {
		t.Fatalf("fetches after cached call = %d, want 1", stub.fetches)
	}

	if _, _, err := e.GetSponsoredMessages("tg", "-1009999"); err != nil {
		t.Fatalf("other chat: %v", err)
	}
	if stub.fetches != 2 {
		t.Fatalf("fetches for other chat = %d, want 2", stub.fetches)
	}

	e.ForTestSponsoredMu().Lock()
	if ent := e.ForTestSponsoredCache()["tg|-1001234"]; ent != nil {
		ent.ForTestSetFetchedAt(time.Now().Add(-6 * time.Minute))
	}
	e.ForTestSponsoredMu().Unlock()
	if _, _, err := e.GetSponsoredMessages("tg", "-1001234"); err != nil {
		t.Fatalf("expired get: %v", err)
	}
	if stub.fetches != 3 {
		t.Fatalf("fetches after expiry = %d, want 3", stub.fetches)
	}

	if _, _, err := e.GetSponsoredMessages("irc", "-1001"); err == nil || !strings.Contains(err.Error(), "does not support sponsored messages") {
		t.Fatalf("plain core error = %v", err)
	}
	if _, _, err := e.GetSponsoredMessages("missing", "-1001"); err == nil || !strings.Contains(err.Error(), "account not found") {
		t.Fatalf("missing account error = %v", err)
	}
}

func TestMarkSponsoredViewedOncePerWindow(t *testing.T) {
	e := newTestEngine(t)
	stub := &sponsoredStub{response: []cores.SponsoredMessageInfo{
		{RandomID: "aabb", Title: "Ad", Message: "buy"},
	}}
	if err := e.AttachAccount("tg", "telegram", stub); err != nil {
		t.Fatal(err)
	}

	if _, _, err := e.GetSponsoredMessages("tg", "-1001"); err != nil {
		t.Fatal(err)
	}
	if err := e.MarkSponsoredViewed("tg", "-1001", "aabb"); err != nil {
		t.Fatalf("view: %v", err)
	}
	if err := e.MarkSponsoredViewed("tg", "-1001", "aabb"); err != nil {
		t.Fatalf("view2: %v", err)
	}
	if len(stub.views) != 1 || stub.views[0] != "aabb" {
		t.Fatalf("views = %v, want [aabb]", stub.views)
	}
}

func TestSponsoredActionsRoute(t *testing.T) {
	e := newTestEngine(t)
	stub := &sponsoredStub{}
	if err := e.AttachAccount("tg", "telegram", stub); err != nil {
		t.Fatal(err)
	}
	if err := e.AttachAccount("irc", "irc", plainStub{}); err != nil {
		t.Fatal(err)
	}

	if err := e.ClickSponsoredMessage("tg", "aabb", false, false); err != nil {
		t.Fatalf("click: %v", err)
	}
	if len(stub.clicks) != 1 || stub.clicks[0] != "aabb" {
		t.Fatalf("clicks = %v", stub.clicks)
	}

	title, opts, err := e.ReportSponsoredMessage("tg", "aabb", "")
	if err != nil {
		t.Fatalf("report: %v", err)
	}
	if title != "What's wrong?" || len(opts) != 2 {
		t.Fatalf("report chain = %q/%d", title, len(opts))
	}
	title, opts, err = e.ReportSponsoredMessage("tg", "aabb", "01")
	if err != nil {
		t.Fatalf("report submit: %v", err)
	}
	if title != "" || opts != nil {
		t.Fatalf("terminal report = %q/%v", title, opts)
	}
	if stub.reports != 2 {
		t.Fatalf("reports = %d, want 2", stub.reports)
	}

	if err := e.ToggleSponsoredMessages("tg", false); err != nil {
		t.Fatalf("toggle: %v", err)
	}
	if len(stub.toggled) != 1 || stub.toggled[0] {
		t.Fatalf("toggled = %v, want [false]", stub.toggled)
	}

	if err := e.ClickSponsoredMessage("irc", "aabb", false, false); err == nil || !strings.Contains(err.Error(), "does not support") {
		t.Fatalf("plain click error = %v", err)
	}
	if err := e.ToggleSponsoredMessages("irc", true); err == nil || !strings.Contains(err.Error(), "does not support") {
		t.Fatalf("plain toggle error = %v", err)
	}
}
