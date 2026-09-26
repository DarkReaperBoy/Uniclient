package cores

import (
	"strings"
	"testing"
)

// TestTsRedactCmdMasksEveryPassword: tsRedactCmd looped but RETURNED
// after redacting the FIRST cpw= occurrence, so any later password in
// the same command reached the debug log in the clear (staticcheck
// SA4004 flagged the never-repeated loop, slice-287).
//
// RED (behavioral, captured before the fix): the second occurrence
// survives — `password visible in redacted log: "...cpw=<redacted>
// ... cpw=secret2"`.
func TestTsRedactCmdMasksEveryPassword(t *testing.T) {
	got := tsRedactCmd("channelpassword cpw=secret1 flags cpw=secret2 more cpw=secret3")
	if strings.Contains(got, "secret1") || strings.Contains(got, "secret2") || strings.Contains(got, "secret3") {
		t.Fatalf("password visible in redacted log: %q", got)
	}
	if n := strings.Count(got, "cpw=<redacted>"); n != 3 {
		t.Fatalf("redacted occurrences = %d, want 3 (log: %q)", n, got)
	}
}

// TestTsRedactCmdPassesThroughCleanCommands: no cpw= → unchanged.
func TestTsRedactCmdPassesThroughCleanCommands(t *testing.T) {
	cmd := "cliententerview name=Alice"
	if got := tsRedactCmd(cmd); got != cmd {
		t.Fatalf("clean command mutated: %q", got)
	}
}

// TestTsRedactCmdSingleOccurrence pins the original single-password
// case that already worked.
func TestTsRedactCmdSingleOccurrence(t *testing.T) {
	got := tsRedactCmd("channelcreate cpw=s3cret")
	if strings.Contains(got, "s3cret") {
		t.Fatalf("password visible: %q", got)
	}
	if !strings.Contains(got, "cpw=<redacted>") {
		t.Fatalf("missing redaction marker: %q", got)
	}
}
