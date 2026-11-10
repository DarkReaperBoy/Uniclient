//go:build !js

package tests

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

var rawTCPFamilies = []string{"telegram", "irc", "xmpp", "deltachat", "teamspeak", "mumble"}

func coresFileIsRawTCP(name string) bool {
	for _, fam := range rawTCPFamilies {
		if name == fam+".go" || strings.HasPrefix(name, fam+"_") {
			return true
		}
	}
	return false
}

func TestRawTCPCoreFilesAreExcludedFromWeb(t *testing.T) {
	entries, err := os.ReadDir(filepath.Join("..", "..", "cores"))
	if err != nil {
		t.Fatalf("read cores dir: %v", err)
	}
	seen := 0
	for _, e := range entries {
		name := e.Name()
		if e.IsDir() || !strings.HasSuffix(name, ".go") {
			continue
		}
		if name == "telegram_data.go" {
			continue
		}
		if !coresFileIsRawTCP(name) {
			continue
		}
		seen++
		raw, err := os.ReadFile(filepath.Join("..", "..", "cores", name))
		if err != nil {
			t.Fatalf("read %s: %v", name, err)
		}
		if !strings.HasPrefix(string(raw), "//go:build !js\n") {
			t.Fatalf("%s belongs to a raw-TCP core family but is not excluded from the web build (first line must be //go:build !js)", name)
		}
	}
	if seen == 0 {
		t.Fatalf("no raw-TCP family files found under ../../cores — the scan is broken")
	}
}

func TestBootstrapFactoryIsBuildSplit(t *testing.T) {
	for file, want := range map[string]string{
		"factory_native.go": "//go:build !js\n",
		"factory_js.go":     "//go:build js\n",
	} {
		raw, err := os.ReadFile(filepath.Join("..", "..", "bootstrap", file))
		if err != nil {
			t.Fatalf("read %s: %v", file, err)
		}
		if !strings.HasPrefix(string(raw), want) {
			t.Fatalf("%s must open with %q", file, strings.TrimSpace(want))
		}
	}
	raw, err := os.ReadFile(filepath.Join("..", "..", "bootstrap", "bootstrap.go"))
	if err != nil {
		t.Fatalf("read bootstrap.go: %v", err)
	}
	if strings.Contains(string(raw), "github.com/gotd/") {
		t.Fatalf("bootstrap.go is shared across builds — the gotd session import belongs to factory_native.go")
	}
}
