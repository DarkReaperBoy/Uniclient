package cores

// telegram_freeze_test.go — regression tests for the owner-reported freeze:
// "clicking on a telegram bot chat froze the client".
//
// Root cause (see the RPC-hygiene section in telegram.go): core methods held
// t.mu across network RPCs; t.ctx has no deadline and gotd runs no heartbeat,
// so a half-open connection hung RPCs forever, pinning the mutex. Go's fair
// RWMutex then starved every queued writer and every later reader.
//
// These tests pin the fixed invariants:
//   1. the chat-open hot path (GetMessages / GetPinnedMessages / GetFullUser /
//      GetChatBotCommands / MarkAsRead) never holds t.mu while an RPC is in
//      flight — a queued writer acquires the lock immediately;
//   2. Logout (the write-lock variant) releases before its RPC too;
//   3. rpcGuard bounds every RPC with a deadline so even a dead connection
//      returns an error instead of hanging forever.

import (
	"context"
	"sync/atomic"
	"testing"
	"time"

	"github.com/gotd/td/bin"
	"github.com/gotd/td/tg"
)

// stuckInvoker blocks inside Invoke FOREVER, ignoring ctx — the worst case of
// a half-open TCP connection below even the rpcGuard deadline. It counts
// entries so tests can prove the caller really reached the RPC.
type stuckInvoker struct {
	release <-chan struct{}
	entered int32
}

func (s *stuckInvoker) Invoke(ctx context.Context, input bin.Encoder, output bin.Decoder) error {
	atomic.AddInt32(&s.entered, 1)
	<-s.release
	return nil
}

// hungInvoker blocks until ctx is canceled — gotd's actual behavior (the rpc
// engine honors context cancellation).
type hungInvoker struct {
	entered  int32
	deadline *time.Time // records the deadline the invoker saw, if any
}

func (h *hungInvoker) Invoke(ctx context.Context, input bin.Encoder, output bin.Decoder) error {
	atomic.AddInt32(&h.entered, 1)
	if d, ok := ctx.Deadline(); ok {
		h.deadline = &d
	}
	<-ctx.Done()
	return ctx.Err()
}

// newFrozenCore returns a TelegramCore whose api client routes every RPC
// into inv (and marks it authed + live).
func newFrozenCore(inv *stuckInvoker) *TelegramCore {
	t := NewTelegramCore(TelegramConfig{})
	t.api = tg.NewClient(inv)
	t.ctx = context.Background()
	t.authed = true
	return t
}

// waitRPCInFlight blocks until the invoker reports at least want calls in
// flight (the method under test has really reached its RPC).
func waitRPCInFlight(t *testing.T, inv *stuckInvoker, want int32) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if atomic.LoadInt32(&inv.entered) >= want {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("RPC never entered flight (invocations=%d, want %d)", atomic.LoadInt32(&inv.entered), want)
}

// probeWriterAcquired checks that a write-lock acquisition on t.mu succeeds
// promptly — i.e. no reader is pinning the mutex across a hung RPC and no
// writer is wedged holding it.
func probeWriterAcquired(t *testing.T, tc *TelegramCore, what string) {
	t.Helper()
	acquired := make(chan struct{})
	go func() {
		tc.mu.Lock()
		close(acquired)
		tc.mu.Unlock()
	}()
	select {
	case <-acquired:
		return
	case <-time.After(2 * time.Second):
		t.Fatalf("%s: t.mu write lock starved for 2s — a reader/writer is pinned across an in-flight RPC (freeze class)", what)
	}
}

// TestChatOpenHotPathsDoNotPinMutex: opening a chat (any chat — a bot DM
// additionally fires GetChatBotCommands) issues its RPCs without holding
// t.mu. With the pre-fix RLock-across-RPC code the probe below starves.
func TestChatOpenHotPathsDoNotPinMutex(t *testing.T) {
	cases := []struct {
		what string
		call func(tc *TelegramCore)
	}{
		{"GetMessages", func(tc *TelegramCore) {
			_, _ = tc.GetMessages("12345", PaginationOpts{Limit: 50})
		}},
		{"GetPinnedMessages", func(tc *TelegramCore) {
			_, _ = tc.GetPinnedMessages("12345")
		}},
		{"GetFullUser", func(tc *TelegramCore) {
			_, _ = tc.GetFullUser("12345")
		}},
		{"GetChatBotCommands (bot DM)", func(tc *TelegramCore) {
			_, _ = tc.GetChatBotCommands("12345")
		}},
		{"MarkAsRead", func(tc *TelegramCore) {
			_ = tc.MarkAsRead("12345", "999")
		}},
	}
	for _, tc := range cases {
		t.Run(tc.what, func(t *testing.T) {
			release := make(chan struct{})
			defer close(release) // un-stick the leaked goroutines on cleanup
			inv := &stuckInvoker{release: release}
			core := newFrozenCore(inv)
			done := make(chan struct{})
			go func() { tc.call(core); close(done) }()
			waitRPCInFlight(t, inv, 1) // provably inside the RPC now
			probeWriterAcquired(t, core, tc.what)
			select {
			case <-done:
				t.Fatalf("%s returned while its RPC is stuck — call did not reach the network path", tc.what)
			default:
			}
		})
	}
}

// TestLogoutDoesNotHoldWriteLockAcrossRPC: Logout used to hold the WRITE
// lock across auth.logOut — the worst variant (blocks every reader).
func TestLogoutDoesNotHoldWriteLockAcrossRPC(t *testing.T) {
	release := make(chan struct{})
	defer close(release)
	inv := &stuckInvoker{release: release}
	core := newFrozenCore(inv)
	done := make(chan struct{})
	go func() { _ = core.Logout(); close(done) }()
	waitRPCInFlight(t, inv, 1)
	// A reader must acquire the lock while the logout RPC is in flight.
	acquired := make(chan struct{})
	go func() {
		core.mu.RLock()
		close(acquired)
		core.mu.RUnlock()
	}()
	select {
	case <-acquired:
	case <-time.After(2 * time.Second):
		t.Fatal("Logout: t.mu read lock starved while the logout RPC is in flight — write lock held across RPC (freeze class)")
	}
}

// TestRPCGuardBoundsHungRPC: every API call routed through rpcGuard carries a
// deadline, so a dead connection surfaces as an error instead of an eternal
// hang.
func TestRPCGuardBoundsHungRPC(t *testing.T) {
	hung := &hungInvoker{}
	guard := rpcGuard{next: hung, timeout: 60 * time.Millisecond}
	start := time.Now()
	err := guard.Invoke(context.Background(), nil, nil)
	if err == nil {
		t.Fatal("guarded invoke of a dead connection unexpectedly succeeded")
	}
	if err != context.DeadlineExceeded {
		t.Fatalf("guarded invoke error = %v, want context.DeadlineExceeded", err)
	}
	if elapsed := time.Since(start); elapsed > 5*time.Second {
		t.Fatalf("guarded invoke took %v — deadline not enforced", elapsed)
	}
}

// TestRPCGuardPreservesCallerDeadline: an explicit caller deadline is never
// widened by the guard.
func TestRPCGuardPreservesCallerDeadline(t *testing.T) {
	hung := &hungInvoker{}
	guard := rpcGuard{next: hung, timeout: time.Hour}
	deadline := time.Now().Add(50 * time.Millisecond)
	ctx, cancel := context.WithDeadline(context.Background(), deadline)
	defer cancel()
	_ = guard.Invoke(ctx, nil, nil)
	if hung.deadline == nil {
		t.Fatal("invoker saw no deadline")
	}
	if !hung.deadline.Equal(deadline) {
		t.Fatalf("guard overrode caller deadline: got %v, want %v", *hung.deadline, deadline)
	}
}

// TestRPCGuardAppliesDefaultDeadline: with no caller deadline the guard
// installs one at the default rpcTimeout.
func TestRPCGuardAppliesDefaultDeadline(t *testing.T) {
	hung := &hungInvoker{}
	guard := rpcGuard{next: hung} // zero timeout → rpcTimeout default
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go func() {
		time.Sleep(50 * time.Millisecond)
		cancel()
	}()
	_ = guard.Invoke(ctx, nil, nil)
	if hung.deadline == nil {
		t.Fatal("invoker saw no deadline — guard did not apply the default")
	}
	remaining := time.Until(*hung.deadline)
	if remaining < 55*time.Second || remaining > 65*time.Second {
		t.Fatalf("default deadline = %v from now, want ~%v", remaining, rpcTimeout)
	}
}

// TestWithAPIRejectsUnauthed: the snapshot helper still enforces auth.
func TestWithAPIRejectsUnauthed(t *testing.T) {
	core := NewTelegramCore(TelegramConfig{})
	if _, _, err := core.withAPI(); err != ErrAuth {
		t.Fatalf("withAPI on unauthed core = %v, want ErrAuth", err)
	}
}

// TestReadPathRPCsDoNotPinMutex: the account/peer read-family methods
// (privacy + gift settings, emoji sets, app-config probes, participant
// lists, folder edits, user photos, global search) must issue their RPCs
// without holding t.mu — same freeze class as the chat-open hot paths.
// Pins the withAPI batch that emptied the read half of the scanner list.
func TestReadPathRPCsDoNotPinMutex(t *testing.T) {
	cases := []struct {
		what string
		call func(tc *TelegramCore)
	}{
		{"GetInstalledEmojiSets", func(tc *TelegramCore) { _, _ = tc.GetInstalledEmojiSets() }},
		{"SetHideReadMarks", func(tc *TelegramCore) { _ = tc.SetHideReadMarks(true) }},
		{"GetCustomEmojiSetInfo", func(tc *TelegramCore) { _, _, _, _, _, _, _ = tc.GetCustomEmojiSetInfo(1) }},
		{"GetGiveawayConfig", func(tc *TelegramCore) { _, _ = tc.GetGiveawayConfig() }},
		{"GetContentSettings", func(tc *TelegramCore) { _, _, _, _ = tc.GetContentSettings() }},
		{"GetAvailableReactionEmojis", func(tc *TelegramCore) { _, _ = tc.GetAvailableReactionEmojis() }},
		{"GetPremiumStatus", func(tc *TelegramCore) { _, _, _ = tc.GetPremiumStatus() }},
		{"GetAllFolderLimits", func(tc *TelegramCore) { _, _ = tc.GetAllFolderLimits() }},
		{"SetMessagesPrivacy", func(tc *TelegramCore) { _ = tc.SetMessagesPrivacy("everyone", 0) }},
		{"SetGiftSettings", func(tc *TelegramCore) { _ = tc.SetGiftSettings(true, true, true, true, true, true) }},
		{"SetPersonalChannel", func(tc *TelegramCore) { _ = tc.SetPersonalChannel("@channel") }},
		{"GetDefaultBannedRights", func(tc *TelegramCore) { _, _ = tc.GetDefaultBannedRights("-1001234567890") }},
		{"AddChatToFolder", func(tc *TelegramCore) { _ = tc.AddChatToFolder("123", 2) }},
		{"GetParticipantsByRole", func(tc *TelegramCore) { _, _, _ = tc.GetParticipantsByRole("-1001234567890", "members", "", 10, 0) }},
		{"GetUserPhotoAtIndex", func(tc *TelegramCore) { _, _, _ = tc.GetUserPhotoAtIndex("123", 0) }},
		{"SearchGlobalPostMessages", func(tc *TelegramCore) { _, _ = tc.SearchGlobalPostMessages("test", 5) }},
		{"CheckCloudPassword", func(tc *TelegramCore) { _ = tc.CheckCloudPassword("pw") }},
		{"SetCloudPassword", func(tc *TelegramCore) { _ = tc.SetCloudPassword("", "new", "hint", "") }},
		{"SetCloudPasswordEmail", func(tc *TelegramCore) { _ = tc.SetCloudPasswordEmail("", "a@b.c") }},
		{"RecoverPasswordWithCode", func(tc *TelegramCore) { _ = tc.RecoverPasswordWithCode("12345", "", "") }},
		{"GetStarsRevenueWithdrawalUrl", func(tc *TelegramCore) { _, _ = tc.GetStarsRevenueWithdrawalUrl("-1001234567890", "pw", 0) }},
		{"GetBroadcastRevenueWithdrawalUrl", func(tc *TelegramCore) { _, _ = tc.GetBroadcastRevenueWithdrawalUrl("-1001234567890", "pw") }},
		{"TransferChannelOwnership", func(tc *TelegramCore) { _ = tc.TransferChannelOwnership("-1001234567890", "123", "pw") }},
	}
	for _, tc := range cases {
		t.Run(tc.what, func(t *testing.T) {
			release := make(chan struct{})
			defer close(release)
			inv := &stuckInvoker{release: release}
			core := newFrozenCore(inv)
			done := make(chan struct{})
			go func() {
				// Post-release, the unstuck RPC returns nil results and some
				// call paths legitimately panic on them — that is cleanup
				// noise, not the failure under test. Swallow it.
				defer func() { _ = recover() }()
				tc.call(core)
				close(done)
			}()
			waitRPCInFlight(t, inv, 1)
			probeWriterAcquired(t, core, tc.what)
			select {
			case <-done:
				t.Fatalf("%s returned while its RPC is stuck — call did not reach the network path", tc.what)
			default:
			}
		})
	}
}
