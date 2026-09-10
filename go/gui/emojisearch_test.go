package gui

import (
	"testing"

	"uniclient/engine"
)

func TestFilterEmojiByKeyword(t *testing.T) {
	kws := []engine.EmojiKeywordEntry{
		{Keyword: "fire", Emoticons: []string{"🔥", "🔥", "🔥"}},
		{Keyword: "firetruck", Emoticons: []string{"🚒"}},
		{Keyword: "smile", Emoticons: []string{"😄", "😃"}},
		{Keyword: "ok", Emoticons: []string{"👍"}},
	}
	if got := filterEmojiByKeyword(kws, "fire", 64); len(got) != 2 || got[0] != "🔥" || got[1] != "🚒" {
		t.Errorf("fire = %v", got)
	}
	if got := filterEmojiByKeyword(kws, "  FIRE ", 64); len(got) != 2 {
		t.Errorf("case/space insensitive = %v", got)
	}
	if got := filterEmojiByKeyword(kws, "fire", 1); len(got) != 1 {
		t.Errorf("cap = %v", got)
	}
	if got := filterEmojiByKeyword(kws, "zzz", 64); len(got) != 0 {
		t.Errorf("no match = %v", got)
	}
	if got := filterEmojiByKeyword(nil, "fire", 64); len(got) != 0 {
		t.Errorf("empty list = %v", got)
	}
	if got := filterEmojiByKeyword(kws, "", 64); len(got) != 0 {
		t.Errorf("empty query = %v", got)
	}
}
