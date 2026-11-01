package engine

import (
	"context"
	"testing"
)

func TestSyncAccountContextNeverNil(t *testing.T) {
	if got := syncAccountContext(nil); got == nil {
		t.Fatal("syncAccountContext(nil) returned nil — a future ctx deref on this path would panic at first login (B-21)")
	}
	base := context.Background()
	if got := syncAccountContext(base); got != base {
		t.Fatal("syncAccountContext must pass a real context through unchanged")
	}
}
