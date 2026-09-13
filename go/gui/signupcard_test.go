package gui

import (
	"testing"
)

// Signup card (slice 193, parity row "Signup (name/photo)" — tdesktop's
// signup asks first+last name separately plus an optional photo that
// uploads as the profile picture right after account creation): pure
// composition + validation locked here.

func TestSignupNameInput(t *testing.T) {
	if got := signupNameInput("Alice", "Smith"); got != "Alice\nSmith" {
		t.Errorf("signupNameInput = %q, want Alice\\nSmith", got)
	}
	if got := signupNameInput("Alice", ""); got != "Alice" {
		t.Errorf("first-only = %q, want Alice", got)
	}
	if got := signupNameInput("  Jo  ", " Lee "); got != "Jo\nLee" {
		t.Errorf("trims = %q, want Jo\\nLee", got)
	}
}

func TestSignupNameValid(t *testing.T) {
	if !signupNameValid("Alice") {
		t.Error("plain name must be valid")
	}
	if !signupNameValid("  Alice  ") {
		t.Error("padded name must be valid (trimmed)")
	}
	if signupNameValid("") {
		t.Error("empty must be invalid")
	}
	if signupNameValid("   ") {
		t.Error("whitespace-only must be invalid")
	}
}

func TestSignupPhotoHint(t *testing.T) {
	if got := signupPhotoHint(""); got != "Add photo" {
		t.Errorf("no-photo hint = %q, want Add photo", got)
	}
	if got := signupPhotoHint("/tmp/p.jpg"); got != "Change photo" {
		t.Errorf("photo hint = %q, want Change photo", got)
	}
}
