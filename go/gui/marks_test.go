package gui

import "testing"

func TestDeletedMarkText(t *testing.T) {
	cases := []struct {
		text, mark, want string
	}{
		{"hello", "", "hello — deleted"},          // default mark
		{"hello", "recalled", "hello recalled"},   // custom suffix
		{"", "", "— deleted"},                     // no text, default
		{"", "gone", "gone"},                      // no text, custom
		{"  ", "gone", "gone"},                    // whitespace-only text
		{"hello", "— deleted", "hello — deleted"}, // explicit default
	}
	for _, c := range cases {
		if got := deletedMarkText(c.text, c.mark); got != c.want {
			t.Errorf("deletedMarkText(%q,%q) = %q, want %q", c.text, c.mark, got, c.want)
		}
	}
}

func TestEditedMark(t *testing.T) {
	if got := editedMark(""); got != defaultEditedMark {
		t.Errorf("editedMark(\"\") = %q, want default %q", got, defaultEditedMark)
	}
	if got := editedMark("changed "); got != "changed " {
		t.Errorf("editedMark custom = %q", got)
	}
}
