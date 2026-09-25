package engine

// tests-first for BUGS.md B-21 — the syncAccount context contract.
//
// finalizeAuth passed `nil` as the context (staticcheck SA1012).
// Today syncAccount never dereferences ctx, so it happens to be safe
// — but the moment any callee uses ctx.Done()/ctx.Err() (the natural
// next edit), first login becomes a nil-context panic. The contract
// is now explicit: a nil context is replaced at the boundary.

import (
	"context"
	"testing"
)

func TestSyncAccountContextNeverNil(t *testing.T) {
	//lint:ignore SA1012 Passing nil is exactly the contract under test (B-21):
	// syncAccountContext must replace it with a real context.
	if got := syncAccountContext(nil); got == nil {
		t.Fatal("syncAccountContext(nil) returned nil — a future ctx deref on this path would panic at first login (B-21)")
	}
	base := context.Background()
	if got := syncAccountContext(base); got != base {
		t.Fatal("syncAccountContext must pass a real context through unchanged")
	}
}
