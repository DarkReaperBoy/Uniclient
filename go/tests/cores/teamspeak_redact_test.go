package tests

import (
	"strings"
	"testing"
	. "uniclient/cores"
)

func TestTsRedactCmdMasksEveryPassword(t *testing.T) {
	got := TsRedactCmd("channelpassword cpw=secret1 flags cpw=secret2 more cpw=secret3")
	if strings.Contains(got, "secret1") || strings.Contains(got, "secret2") || strings.Contains(got, "secret3") {
		t.Fatalf("password visible in redacted log: %q", got)
	}
	if n := strings.Count(got, "cpw=<redacted>"); n != 3 {
		t.Fatalf("redacted occurrences = %d, want 3 (log: %q)", n, got)
	}
}

func TestTsRedactCmdPassesThroughCleanCommands(t *testing.T) {
	cmd := "cliententerview name=Alice"
	if got := TsRedactCmd(cmd); got != cmd {
		t.Fatalf("clean command mutated: %q", got)
	}
}

func TestTsRedactCmdSingleOccurrence(t *testing.T) {
	got := TsRedactCmd("channelcreate cpw=s3cret")
	if strings.Contains(got, "s3cret") {
		t.Fatalf("password visible: %q", got)
	}
	if !strings.Contains(got, "cpw=<redacted>") {
		t.Fatalf("missing redaction marker: %q", got)
	}
}
