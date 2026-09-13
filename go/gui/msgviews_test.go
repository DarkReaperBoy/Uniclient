package gui

// Channel-post views (slice 187): the compact counter label.

import "testing"

func TestViewsCountLabel(t *testing.T) {
	cases := []struct {
		n    int
		want string
	}{
		{0, "0"},
		{7, "7"},
		{999, "999"},
		{1000, "1.0K"},
		{1234, "1.2K"},
		{9999, "10.0K"},
		{10000, "10K"},
		{15400, "15K"},
		{999999, "999K"},
		{1000000, "1.0M"},
		{1234567, "1.2M"},
		{15400000, "15M"},
	}
	for _, c := range cases {
		if got := viewsCountLabel(c.n); got != c.want {
			t.Errorf("viewsCountLabel(%d) = %q, want %q", c.n, got, c.want)
		}
	}
}
