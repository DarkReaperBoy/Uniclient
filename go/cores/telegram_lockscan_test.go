package cores

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// TestNoLockAcrossRPC (slice 192): pins the §8 invariant — no TelegramCore
// method may hold t.mu (read OR write) across an RPC. Scans the source at
// test time for the deferred-lock + t.api.* co-occurrence; the v2
// lock-state scanner covered write locks, this catches the read-lock form
// that 31 methods (boosts/stats/star-ref/notify-sound/read-participants)
// still had after the "COMPLETE" report — a regression here reintroduces
// the owner-reported freeze class (writers blocked behind a hung RPC).
func TestNoLockAcrossRPC(t *testing.T) {
	files, err := filepath.Glob("telegram*.go")
	if err != nil || len(files) == 0 {
		t.Fatalf("glob telegram*.go: %v (%d files)", err, len(files))
	}
	fnRe := regexp.MustCompile(`(?s)func \(t \*TelegramCore\) (\w+)\(.*?\n}`)
	rlockRe := regexp.MustCompile(`t\.mu\.RLock\(\)\s*\n\tdefer t\.mu\.RUnlock\(\)`)
	lockRe := regexp.MustCompile(`t\.mu\.Lock\(\)\s*\n\tdefer t\.mu\.Unlock\(\)`)
	apiRe := regexp.MustCompile(`t\.api\.\w+\(`)
	var bad []string
	for _, f := range files {
		if strings.HasSuffix(f, "_test.go") {
			continue
		}
		src, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		for _, m := range fnRe.FindAllStringSubmatch(string(src), -1) {
			name, body := m[1], m[0]
			if (rlockRe.MatchString(body) || lockRe.MatchString(body)) && apiRe.MatchString(body) {
				bad = append(bad, f+" → "+name)
			}
		}
	}
	if len(bad) > 0 {
		t.Fatalf("lock held across RPC (§8 freeze class) in:\n%s", strings.Join(bad, "\n"))
	}
}
