package engine

import (
	"strings"
	"testing"

	"uniclient/cores"
)

// storyLinkStub: a core exposing the story surfaces (reactor + link exporter).
type storyLinkStub struct {
	cores.StubCore
	reacted  map[string]string // chatID|storyID → emoji ("" = removed)
	exported []int
	link     string
}

func (s *storyLinkStub) ReactToStory(userID string, storyID int, emoji string) error {
	if s.reacted == nil {
		s.reacted = map[string]string{}
	}
	s.reacted[userID+"|"+string(rune('0'+storyID))] = emoji
	return nil
}

func (s *storyLinkStub) ExportStoryLink(peerID string, storyID int) (string, error) {
	s.exported = append(s.exported, storyID)
	if s.link != "" {
		return s.link, nil
	}
	return "https://t.me/story/1", nil
}

func TestEngineReactToStory(t *testing.T) {
	e := newTestEngine(t)
	stub := &storyLinkStub{}
	e.accounts = map[string]*Account{
		"tg":  {ID: "tg", Core: stub},
		"irc": {ID: "irc", Core: plainStub{}},
	}
	if err := e.ReactToStory("tg", "42", 7, "👍"); err != nil {
		t.Fatalf("react: %v", err)
	}
	if stub.reacted["42|7"] != "👍" {
		t.Fatalf("stub saw %q, want 👍", stub.reacted["42|7"])
	}
	// Empty emoji = remove the reaction (tdesktop tap-again semantics).
	if err := e.ReactToStory("tg", "42", 7, ""); err != nil {
		t.Fatalf("remove reaction: %v", err)
	}
	if stub.reacted["42|7"] != "" {
		t.Fatalf("stub saw %q after removal, want empty", stub.reacted["42|7"])
	}
	if err := e.ReactToStory("irc", "42", 7, "👍"); err == nil || !strings.Contains(err.Error(), "does not support story reactions") {
		t.Fatalf("plain core must report unsupported, got %v", err)
	}
	if err := e.ReactToStory("missing", "42", 7, "👍"); err == nil || !strings.Contains(err.Error(), "account not found") {
		t.Fatalf("missing account error, got %v", err)
	}
}

func TestEngineExportStoryLink(t *testing.T) {
	e := newTestEngine(t)
	stub := &storyLinkStub{link: "https://t.me/test/5"}
	e.accounts = map[string]*Account{
		"tg":  {ID: "tg", Core: stub},
		"irc": {ID: "irc", Core: plainStub{}},
	}
	link, err := e.ExportStoryLink("tg", "42", 7)
	if err != nil {
		t.Fatalf("export: %v", err)
	}
	if link != "https://t.me/test/5" {
		t.Fatalf("link = %q", link)
	}
	if len(stub.exported) != 1 || stub.exported[0] != 7 {
		t.Fatalf("stub exported %v, want [7]", stub.exported)
	}
	if _, err := e.ExportStoryLink("irc", "42", 7); err == nil || !strings.Contains(err.Error(), "does not support story links") {
		t.Fatalf("plain core must report unsupported, got %v", err)
	}
	if _, err := e.ExportStoryLink("missing", "42", 7); err == nil || !strings.Contains(err.Error(), "account not found") {
		t.Fatalf("missing account error, got %v", err)
	}
}
