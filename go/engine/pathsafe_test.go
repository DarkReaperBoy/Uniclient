package engine

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSafePathSegmentKeepsLegitIDs(t *testing.T) {
	for _, in := range []string{
		"$RkmbQfKaQnHqj:matrix.org",
		"-1001234567890",
		"event_0.bin",
		"profilemusic_12345.mp3",
		"uc-live-48291",
	} {
		if got := safePathSegment(in); got != in {
			t.Errorf("safePathSegment(%q) = %q, want unchanged", in, got)
		}
	}
}

func TestSafePathSegmentNeutralizesTraversal(t *testing.T) {
	cases := map[string]string{
		"../../etc/passwd": "passwd",
		"..":               "file",
		".":                "file",
		"":                 "file",
		"a/b/c":            "c",
		`..\..\evil`:       "evil",
		"/abs/path":        "path",
		"x/../../y":        "y",
		"   ":              "file",
	}
	for in, want := range cases {
		got := safePathSegment(in)
		if got != want {
			t.Errorf("safePathSegment(%q) = %q, want %q", in, got, want)
		}
		if strings.ContainsAny(got, `/\`) || got == ".." || got == "." {
			t.Errorf("safePathSegment(%q) = %q still unsafe", in, got)
		}
	}
}

func TestSafePathSegmentNeverEscapesDir(t *testing.T) {
	dir := t.TempDir()
	for _, evil := range []string{"../../../tmp/pwned", "..\\..\\pwned", "..", "/etc/shadow"} {
		p := filepath.Join(dir, safePathSegment(evil))
		clean := filepath.Clean(p)
		if !strings.HasPrefix(clean, filepath.Clean(dir)+string(os.PathSeparator)) {
			t.Errorf("escaped: Join(dir, %q) = %q", evil, clean)
		}
	}
}

func TestRawServerIDJoinsGone(t *testing.T) {
	sites := map[string]string{
		"media.go":       "filepath.Join(dir, job.MsgID+",
		"mediastream.go": "filepath.Join(dir, msgID+",
	}
	for file, raw := range sites {
		src, err := os.ReadFile(file)
		if err != nil {
			t.Fatalf("read %s: %v", file, err)
		}
		for _, line := range strings.Split(string(src), "\n") {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "//") {
				continue
			}
			if strings.Contains(line, raw) {
				t.Errorf("%s still joins a raw server ID: %s", file, trimmed)
			}
		}
	}
	src, err := os.ReadFile("pending.go")
	if err != nil {
		t.Fatalf("read pending.go: %v", err)
	}
	for _, line := range strings.Split(string(src), "\n") {
		if strings.TrimSpace(line) == "//" {
			continue
		}
		if (strings.Contains(line, "filepath.Join(tmpDir, msgID+") ||
			strings.Contains(line, "filepath.Join(tmpDir, p.MsgID+")) &&
			!strings.Contains(line, "safePathSegment") {
			t.Errorf("pending.go still joins a raw server ID: %s", strings.TrimSpace(line))
		}
	}
}
