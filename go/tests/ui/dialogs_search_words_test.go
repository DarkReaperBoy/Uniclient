package tests

import (
	"testing"

	. "uniclient/ui/dialogs"
)

func eqWordList(got, want []string) bool {
	if len(got) != len(want) {
		return false
	}
	for i := range got {
		if got[i] != want[i] {
			return false
		}
	}
	return true
}

func TestSearchWordsLaw(t *testing.T) {
	cases := []struct {
		name  string
		query string
		want  []string
	}{
		{"trim lower split", "  Sarah  Connor! ", []string{"sarah", "connor"}},
		{"splitter set", "a@b-c+d(e)f[g]h{i}j<k>l,m.n:o!p_q;r\"s't", []string{"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t"}},
		{"nul splits", "a\x00b", []string{"a", "b"}},
		{"garbage only", "!!! ... ;;; ''", []string{}},
		{"spaces only", "   ", []string{}},
		{"accents fold", "José Ünal", []string{"jose", "unal"}},
		{"cjk keeps whole words", "张三 李四", []string{"张三", "李四"}},
	}
	for _, tc := range cases {
		if got := SearchWords(tc.query); !eqWordList(got, tc.want) {
			t.Fatalf("%s: SearchWords(%q) = %v, want %v", tc.name, tc.query, got, tc.want)
		}
	}
}

func TestNameWordsUsernameLaw(t *testing.T) {
	cases := []struct {
		name     string
		title    string
		username string
		query    string
		want     bool
	}{
		{"username word in index", "Alice", "alice", "ali", true},
		{"username prefix", "Alice", "al1ce", "al1", true},
		{"query hits username only", "Alice", "sunfire", "sun", true},
		{"query hits name only", "Alice", "sunfire", "ali", true},
		{"at sign splits to username word", "Alice", "al1ce", "@al1", true},
		{"no username falls back to name", "Alice", "", "ali", true},
		{"no username keeps name law", "Alice", "", "sun", false},
		{"name and username must both match", "Alice", "sunfire", "alice sun", true},
		{"missing username word fails", "Alice", "sunfire", "sunfire2", false},
		{"username dedups name word", "Alice", "alice", "alice", true},
	}
	for _, tc := range cases {
		index := NameWords(tc.title, tc.username)
		got := MatchesNameWords(index, SearchWords(tc.query))
		if got != tc.want {
			t.Fatalf("%s: NameWords(%q, %q) = %v against %q, want %v", tc.name, tc.title, tc.username, index, tc.query, tc.want)
		}
	}
}

func TestNameWordsDedup(t *testing.T) {
	index := NameWords("Alice", "alice")
	if len(index) != 1 || index[0] != "alice" {
		t.Fatalf("NameWords(Alice, alice) = %v, want [alice]", index)
	}
	index = NameWords("Alice Smith", "alice")
	if len(index) != 2 || index[0] != "alice" || index[1] != "smith" {
		t.Fatalf("NameWords(Alice Smith, alice) = %v, want [alice smith]", index)
	}
	index = NameWords("", "")
	if len(index) != 0 {
		t.Fatalf("NameWords(empty) = %v, want []", index)
	}
}

func TestMatchesNameWordsPrefixLaw(t *testing.T) {
	cases := []struct {
		name  string
		title string
		query string
		want  bool
	}{
		{"word prefix", "Sarah Connor", "sa", true},
		{"second word prefix", "Sarah Connor", "conn", true},
		{"mid word is not a prefix", "Sarah Connor", "rah", false},
		{"every word must match", "Sarah Connor", "sarah connor", true},
		{"one word missing fails", "Sarah Connor", "sarah carol", false},
		{"case folds", "SARAH connor", "SaRaH", true},
		{"accent folds both sides", "Ünal Öztürk", "ozt", true},
		{"accent folds query", "Ünal", "unal", true},
		{"accent folds title", "Ünal", "UNA", true},
		{"cjk prefix", "张三丰", "张三", true},
		{"cjk non prefix", "张三丰", "三丰", false},
		{"cjk exact title", "张三丰", "张三丰", true},
		{"garbage query matches all", "Sarah Connor", "!!!", true},
		{"empty query matches all", "Sarah Connor", "", true},
		{"prefix overflow fails", "Sarah", "sarahx", false},
		{"no empty word from split", "Sarah Connor", "s ", true},
	}
	for _, tc := range cases {
		got := MatchesNameWords(NameWords(tc.title, ""), SearchWords(tc.query))
		if got != tc.want {
			t.Fatalf("%s: MatchesNameWords(NameWords(%q, \"\"), %q) = %v, want %v", tc.name, tc.title, tc.query, got, tc.want)
		}
	}
}
