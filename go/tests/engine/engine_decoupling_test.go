package tests

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func engineSourceFiles(t *testing.T) []string {
	t.Helper()
	dir := filepath.Join("..", "..", "engine")
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("read engine dir: %v", err)
	}
	var files []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".go") {
			files = append(files, filepath.Join(dir, e.Name()))
		}
	}
	if len(files) == 0 {
		t.Fatalf("no engine sources found under %s", dir)
	}
	return files
}

func TestEngineImportsNoCoreSDK(t *testing.T) {
	for _, path := range engineSourceFiles(t) {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("read %s: %v", path, err)
		}
		for _, line := range strings.Split(string(raw), "\n") {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "\"github.com/gotd/") {
				t.Fatalf("%s imports a core SDK (%s) — the engine speaks cores.Core and capability interfaces only", filepath.Base(path), trimmed)
			}
		}
	}
}

func TestEngineAssertsNoConcreteCore(t *testing.T) {
	re := regexp.MustCompile(`\*cores\.(TelegramCore|MatrixCore|BaleCore|IRCCore|XMPPCore|DeltaChatCore|TeamSpeakCore|MumbleCore|GitHubCore|StubCore)\b`)
	for _, path := range engineSourceFiles(t) {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("read %s: %v", path, err)
		}
		if loc := re.FindIndex(raw); loc != nil {
			line := 1 + strings.Count(string(raw[:loc[0]]), "\n")
			t.Fatalf("%s:%d references a concrete core type (%q) — the engine projects capabilities through interfaces, never core concretes; a new core joins the roster by extending this pin", filepath.Base(path), line, re.Find(raw))
		}
	}
}
