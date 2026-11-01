package gui

import (
	"testing"

	"uniclient/engine"
)

func TestPostsSearchQuery(t *testing.T) {
	cases := []struct {
		q    string
		want bool
	}{
		{"#news", true},
		{"#a", true},
		{"#", false},
		{"news", false},
		{"# News", false},
		{"", false},
		{"  #news", false},
	}
	for _, c := range cases {
		if got := postsSearchQuery(c.q); got != c.want {
			t.Errorf("postsSearchQuery(%q) = %v, want %v", c.q, got, c.want)
		}
	}
}

func TestBuildSearchRowsPosts(t *testing.T) {
	chats := []engine.ChatInfo{{AccountID: "a1", ChatID: "1", Title: "Alpha"}}
	msgs := []engine.SearchResult{{AccountID: "a1", ChatID: "1", MsgID: "5", Text: "hello"}}
	posts := []engine.SearchResult{{AccountID: "a1", ChatID: "-100777", MsgID: "9", Text: "#news breaking", ChatTitle: "Daily"}}
	global := []engine.ChatInfo{{AccountID: "a1", ChatID: "-100888", Title: "News Channel"}}

	rows := buildSearchRows(chats, msgs, posts, global, "")
	titles := sectionTitles(rows)
	want := []string{"Chats", "Messages", "Posts", "Global results"}
	if len(titles) != len(want) {
		t.Fatalf("sections = %v, want %v", titles, want)
	}
	for i := range want {
		if titles[i] != want[i] {
			t.Fatalf("sections = %v, want %v", titles, want)
		}
	}

	found := false
	for _, r := range rows {
		if r.kind == sbRowMsg && r.msg != nil && r.msg.MsgID == "9" {
			found = true
		}
	}
	if !found {
		t.Fatal("post hit missing from rows")
	}

	rows = buildSearchRows(chats, msgs, nil, global, "")
	for _, r := range rows {
		if r.kind == sbRowHeader && r.title == "Posts" {
			t.Fatal("Posts header must not render without post hits")
		}
	}
}

func TestFilterSearchRowsPosts(t *testing.T) {
	posts := []engine.SearchResult{{AccountID: "a1", ChatID: "-100777", MsgID: "9", Text: "#news", ChatTitle: "Daily"}}
	msgs := []engine.SearchResult{{AccountID: "a1", ChatID: "1", MsgID: "5", Text: "hello"}}
	rows := buildSearchRows(nil, msgs, posts, nil, "")

	hasPosts := func(rs []sbRow) bool {
		for _, r := range rs {
			if r.kind == sbRowHeader && r.title == "Posts" {
				return true
			}
		}
		return false
	}
	if !hasPosts(filterSearchRows(rows, searchTabAll)) {
		t.Fatal("Posts missing on All tab")
	}
	if !hasPosts(filterSearchRows(rows, searchTabMsgs)) {
		t.Fatal("Posts missing on Messages tab")
	}
	if hasPosts(filterSearchRows(rows, searchTabChats)) {
		t.Fatal("Posts must not render on Chats tab")
	}
	if hasPosts(filterSearchRows(rows, searchTabLinks)) {
		t.Fatal("Posts must not render on Links tab")
	}
	if hasPosts(filterSearchRows(rows, searchTabFiles)) {
		t.Fatal("Posts must not render on Files tab")
	}
}

func sectionTitles(rows []sbRow) []string {
	var out []string
	for _, r := range rows {
		if r.kind == sbRowHeader {
			out = append(out, r.title)
		}
	}
	return out
}
