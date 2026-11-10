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

func TestMatchesWordsPrefixLaw(t *testing.T) {
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
		got := MatchesWords(tc.title, SearchWords(tc.query))
		if got != tc.want {
			t.Fatalf("%s: MatchesWords(%q, %q) = %v, want %v", tc.name, tc.title, tc.query, got, tc.want)
		}
	}
}
