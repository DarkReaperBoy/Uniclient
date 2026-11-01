package gui

import (
	"testing"
)

func TestValidateUsername(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{"", ""},
		{"abc", "at least 5 characters"},
		{"ab", "at least 5 characters"},
		{"abcdefghijklmnopqrstuvwxyz1234567", "at most 32 characters"},
		{"valid_user", ""},
		{"ValidUser", ""},
		{"_leading", "must start with a letter"},
		{"9numbers", "must start with a letter"},
		{"has-dash", "only letters, digits and _"},
		{"has space", "only letters, digits and _"},
		{"has.dot", "only letters, digits and _"},
	}
	for _, c := range cases {
		if got := validateUsername(c.in); got != c.want {
			t.Errorf("validateUsername(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestValidateBio(t *testing.T) {
	if got := validateBio(""); got != "" {
		t.Errorf("empty bio must be allowed, got %q", got)
	}
	if got := validateBio(stringOf('x', 70)); got != "" {
		t.Errorf("70 chars must pass, got %q", got)
	}
	if got := validateBio(stringOf('x', 71)); got != "at most 70 characters" {
		t.Errorf("71 chars must fail, got %q", got)
	}
}

func stringOf(c byte, n int) string {
	b := make([]byte, n)
	for i := range b {
		b[i] = c
	}
	return string(b)
}

func TestParseBirthday(t *testing.T) {
	d, m, y, err := parseBirthday("", "", "")
	if err != "" || d != 0 || m != 0 || y != 0 {
		t.Fatalf("empty = clear, got %d/%d/%d %q", d, m, y, err)
	}
	d, m, y, err = parseBirthday("14", "03", "1990")
	if err != "" || d != 14 || m != 3 || y != 1990 {
		t.Fatalf("valid date, got %d/%d/%d %q", d, m, y, err)
	}
	if _, _, _, err := parseBirthday("14", "", ""); err == "" {
		t.Fatal("partial date must error")
	}
	if _, _, _, err := parseBirthday("32", "1", "1990"); err == "" {
		t.Fatal("day 32 must error")
	}
	if _, _, _, err := parseBirthday("31", "2", "1990"); err == "" {
		t.Fatal("Feb 31 must error")
	}
	if _, _, _, err := parseBirthday("1", "13", "1990"); err == "" {
		t.Fatal("month 13 must error")
	}
	if _, _, _, err := parseBirthday("1", "1", "1790"); err == "" {
		t.Fatal("year 1790 must error")
	}
	if _, _, _, err := parseBirthday("1", "1", ""); err != "" {
		t.Fatalf("year-less date must pass, got %q", err)
	}
	if _, _, _, err := parseBirthday("ab", "1", "1990"); err == "" {
		t.Fatal("non-numeric day must error")
	}
}

func TestBirthdayLabel(t *testing.T) {
	if got := birthdayLabel(0, 0, 0); got != "not set" {
		t.Errorf("unset: %q", got)
	}
	if got := birthdayLabel(14, 3, 1990); got != "Mar 14, 1990" {
		t.Errorf("full: %q", got)
	}
	if got := birthdayLabel(1, 1, 0); got != "Jan 1" {
		t.Errorf("year-less: %q", got)
	}
}
