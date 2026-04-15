package utils

import (
	"os"
	"path/filepath"
	"testing"
)

type testSession struct {
	Token  string `json:"token"`
	UserID int64  `json:"user_id"`
	Extra  string `json:"extra,omitempty"`
}

func TestSaveAndLoadSession(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "session.json")

	orig := testSession{Token: "abc123", UserID: 42, Extra: "hello"}
	if err := SaveSession(path, &orig); err != nil {
		t.Fatalf("SaveSession: %v", err)
	}

	// Verify file exists with correct permissions
	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	if perm := info.Mode().Perm(); perm != 0600 {
		t.Errorf("permissions = %o, want 0600", perm)
	}

	var loaded testSession
	if err := LoadSession(path, &loaded); err != nil {
		t.Fatalf("LoadSession: %v", err)
	}
	if loaded.Token != orig.Token || loaded.UserID != orig.UserID || loaded.Extra != orig.Extra {
		t.Errorf("loaded = %+v, want %+v", loaded, orig)
	}
}

func TestLoadSessionNotExist(t *testing.T) {
	var sess testSession
	err := LoadSession("/tmp/nonexistent_session_test_12345.json", &sess)
	if err != nil {
		t.Fatalf("expected nil error for missing file, got: %v", err)
	}
	if sess.Token != "" {
		t.Errorf("expected zero value, got %+v", sess)
	}
}

func TestSaveSessionCreatesParentDirs(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "a", "b", "c", "session.json")

	sess := testSession{Token: "nested"}
	if err := SaveSession(path, &sess); err != nil {
		t.Fatalf("SaveSession with nested dirs: %v", err)
	}

	var loaded testSession
	if err := LoadSession(path, &loaded); err != nil {
		t.Fatalf("LoadSession: %v", err)
	}
	if loaded.Token != "nested" {
		t.Errorf("token = %q, want %q", loaded.Token, "nested")
	}
}
