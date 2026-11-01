package tests

import (
	"context"
	"testing"
	. "uniclient/engine"
)

func TestSyncAccountContextNeverNil(t *testing.T) {
	if got := SyncAccountContext(nil); got == nil {
		t.Fatal("syncAccountContext(nil) returned nil — a future ctx deref on this path would panic at first login (B-21)")
	}
	base := context.Background()
	if got := SyncAccountContext(base); got != base {
		t.Fatal("syncAccountContext must pass a real context through unchanged")
	}
}
