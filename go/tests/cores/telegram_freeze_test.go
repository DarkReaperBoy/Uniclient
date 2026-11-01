package tests

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"
	. "uniclient/cores"

	"github.com/gotd/td/bin"
	"github.com/gotd/td/tg"
)

type stuckInvoker struct {
	release <-chan struct{}
	entered int32
}

func (s *stuckInvoker) Invoke(ctx context.Context, input bin.Encoder, output bin.Decoder) error {
	atomic.AddInt32(&s.entered, 1)
	<-s.release
	return nil
}

type hungInvoker struct {
	entered  int32
	deadline *time.Time
}

func (h *hungInvoker) Invoke(ctx context.Context, input bin.Encoder, output bin.Decoder) error {
	atomic.AddInt32(&h.entered, 1)
	if d, ok := ctx.Deadline(); ok {
		h.deadline = &d
	}
	<-ctx.Done()
	return ctx.Err()
}

func newFrozenCore(inv *stuckInvoker) *TelegramCore {
	t := NewTelegramCore(TelegramConfig{})
	t.ForTestSetApi(tg.NewClient(inv))
	t.ForTestSetCtx(context.Background())
	t.ForTestSetAuthed(true)
	return t
}

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

func probeWriterAcquired(t *testing.T, tc *TelegramCore, what string) {
	t.Helper()
	acquired := make(chan struct{})
	go func() {
		tc.ForTestMu().Lock()
		close(acquired)
		tc.ForTestMu().Unlock()
	}()
	select {
	case <-acquired:
		return
	case <-time.After(2 * time.Second):
		t.Fatalf("%s: t.mu write lock starved for 2s — a reader/writer is pinned across an in-flight RPC (freeze class)", what)
	}
}

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
			defer close(release)
			inv := &stuckInvoker{release: release}
			core := newFrozenCore(inv)
			done := make(chan struct{})
			go func() { tc.call(core); close(done) }()
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

func TestLogoutDoesNotHoldWriteLockAcrossRPC(t *testing.T) {
	release := make(chan struct{})
	defer close(release)
	inv := &stuckInvoker{release: release}
	core := newFrozenCore(inv)
	done := make(chan struct{})
	go func() { _ = core.Logout(); close(done) }()
	waitRPCInFlight(t, inv, 1)
	acquired := make(chan struct{})
	go func() {
		core.ForTestMu().RLock()
		close(acquired)
		core.ForTestMu().RUnlock()
	}()
	select {
	case <-acquired:
	case <-time.After(2 * time.Second):
		t.Fatal("Logout: t.mu read lock starved while the logout RPC is in flight — write lock held across RPC (freeze class)")
	}
}

func TestRPCGuardBoundsHungRPC(t *testing.T) {
	hung := &hungInvoker{}
	guard := *ForTestNewRpcGuard(hung, 60*time.Millisecond)
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

func TestRPCGuardPreservesCallerDeadline(t *testing.T) {
	hung := &hungInvoker{}
	guard := *ForTestNewRpcGuard(hung, time.Hour)
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

func TestRPCGuardAppliesDefaultDeadline(t *testing.T) {
	hung := &hungInvoker{}
	guard := *ForTestNewRpcGuard(hung, 0)
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
		t.Fatalf("default deadline = %v from now, want ~%v", remaining, RpcTimeout)
	}
}

func TestWithAPIRejectsUnauthed(t *testing.T) {
	core := NewTelegramCore(TelegramConfig{})
	if _, _, err := core.WithAPI(); err != ErrAuth {
		t.Fatalf("WithAPI on unauthed core = %v, want ErrAuth", err)
	}
}

func TestReadPathRPCsDoNotPinMutex(t *testing.T) {
	cases := []struct {
		what string
		call func(tc *TelegramCore)
	}{
		{"GetInstalledEmojiSets", func(tc *TelegramCore) { _, _ = tc.GetInstalledEmojiSets() }},
		{"SetHideReadMarks", func(tc *TelegramCore) { _ = tc.SetHideReadMarks(true) }},
		{"GetCustomEmojiSetInfo", func(tc *TelegramCore) { _, _, _, _, _, _, _ = tc.GetCustomEmojiSetInfo(1) }},
		{"GetStarsGiveawayOptions", func(tc *TelegramCore) { _, _ = tc.GetStarsGiveawayOptions() }},
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
		{"UploadProfilePhoto", func(tc *TelegramCore) { _ = tc.UploadProfilePhoto([]byte{0x89, 'P', 'N', 'G'}) }},
		{"SetBotPhoto", func(tc *TelegramCore) { _ = tc.SetBotPhoto("123", []byte{0x89, 'P', 'N', 'G'}) }},
		{"UploadFallbackPhoto", func(tc *TelegramCore) { _ = tc.UploadFallbackPhoto([]byte{0x89, 'P', 'N', 'G'}) }},
		{"DeleteFallbackPhoto", func(tc *TelegramCore) { _ = tc.DeleteFallbackPhoto() }},
		{"DeleteProfilePhotos", func(tc *TelegramCore) { _ = tc.DeleteProfilePhotos() }},
		{"EditChannelPhoto", func(tc *TelegramCore) { _ = tc.EditChannelPhoto("-1001234567890", []byte{0x89, 'P', 'N', 'G'}) }},
		{"EditChannelVideoPhoto", func(tc *TelegramCore) { _ = tc.EditChannelVideoPhoto("-1001234567890", []byte{0, 0, 0, 1}) }},
		{"CreateCloudThemeWithData", func(tc *TelegramCore) { _, _ = tc.CreateCloudThemeWithData("t", "s", []byte("theme")) }},
		{"UpdateCloudThemeWithData", func(tc *TelegramCore) { _, _ = tc.UpdateCloudThemeWithData(1, 2, "t", "s", []byte("theme")) }},
		{"SendMediaAlbum", func(tc *TelegramCore) {
			items := []AlbumItem{{Upload: FileUpload{Name: "a.png", MimeType: "image/png", Size: 4, Reader: bytes.NewReader([]byte{0x89, 'P', 'N', 'G'})}, IsPhoto: true}}
			_, _ = tc.SendMediaAlbum("123", items, false, 0)
		}},
		{"SendImageBase64", func(tc *TelegramCore) { _, _ = tc.SendImageBase64("123", "aVBORw==", "cap") }},
		{"GetDifferenceCheck", func(tc *TelegramCore) { _ = tc.GetDifferenceCheck() }},
		{"DownloadWallpaperDocument", func(tc *TelegramCore) { _, _ = tc.DownloadWallpaperDocument(1, 2, []byte("ref")) }},
		{"UploadFile", func(tc *TelegramCore) {
			_, _ = tc.UploadFile("123", FileUpload{Name: "f.png", MimeType: "image/png", Size: 4, Reader: bytes.NewReader([]byte{0x89, 'P', 'N', 'G'})}, nil)
		}},
		{"UploadFileWithOptions", func(tc *TelegramCore) {
			_, _ = tc.UploadFileWithOptions("123", FileUpload{Name: "f.png", MimeType: "image/png", Size: 4, Reader: bytes.NewReader([]byte{0x89, 'P', 'N', 'G'})}, UploadOptions{}, nil)
		}},
		{"SendStoryWithPhoto", func(tc *TelegramCore) {
			_, _ = tc.SendStoryWithPhoto("cap", []byte{0x89, 'P', 'N', 'G'}, StoryPostOptions{})
		}},
		{"SendStoryWithVideoFile", func(tc *TelegramCore) {
			tmp := filepath.Join(os.TempDir(), "freeze_story.mp4")
			if err := os.WriteFile(tmp, []byte("\x00\x00\x00\x18ftypmp42"), 0o600); err != nil {
				t.Fatal(err)
			}
			_, _ = tc.SendStoryWithVideoFile("cap", tmp, StoryPostOptions{})
		}},
	}
	for _, tc := range cases {
		t.Run(tc.what, func(t *testing.T) {
			release := make(chan struct{})
			defer close(release)
			inv := &stuckInvoker{release: release}
			core := newFrozenCore(inv)
			done := make(chan struct{})
			go func() {
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
