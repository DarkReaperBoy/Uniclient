package tests

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
	. "uniclient/cores"

	"github.com/gotd/td/tg"
)

func TestChatOpenHotPathsDoNotPinMutex(t *testing.T) {
	s := newTGScriptedServer(t)
	cases := []struct {
		what string
		rpc  uint32
		call func(tc *TelegramCore)
	}{
		{"GetMessages", tg.MessagesGetHistoryRequestTypeID, func(tc *TelegramCore) {
			_, _ = tc.GetMessages("12345", PaginationOpts{Limit: 50})
		}},
		{"GetPinnedMessages", tg.MessagesSearchRequestTypeID, func(tc *TelegramCore) {
			_, _ = tc.GetPinnedMessages("12345")
		}},
		{"GetFullUser", tg.UsersGetFullUserRequestTypeID, func(tc *TelegramCore) {
			_, _ = tc.GetFullUser("12345")
		}},
		{"GetChatBotCommands (bot DM)", tg.UsersGetFullUserRequestTypeID, func(tc *TelegramCore) {
			_, _ = tc.GetChatBotCommands("12345")
		}},
		{"MarkAsRead", tg.MessagesReadHistoryRequestTypeID, func(tc *TelegramCore) {
			_ = tc.MarkAsRead("12345", "999")
		}},
	}
	for _, tc := range cases {
		t.Run(tc.what, func(t *testing.T) {
			core := s.authedCore(t)
			stuck := s.stickNext(tc.rpc)
			t.Cleanup(func() { close(stuck.release) })
			go func() {
				defer func() { _ = recover() }()
				tc.call(core)
			}()
			waitStuckEntered(t, stuck, tc.what)
			probe := s.watchType(tg.AuthLogOutRequestTypeID)
			go func() { _ = core.Logout() }()
			waitWatched(t, probe, tc.what+": Logout write-lock probe")
		})
	}
}

func TestLogoutDoesNotHoldWriteLockAcrossRPC(t *testing.T) {
	s := newTGScriptedServer(t)
	core := s.authedCore(t)
	stuck := s.stickNext(tg.AuthLogOutRequestTypeID)
	t.Cleanup(func() { close(stuck.release) })
	logoutDone := make(chan struct{})
	go func() {
		defer close(logoutDone)
		_ = core.Logout()
	}()
	waitStuckEntered(t, stuck, "Logout")
	probeDone := make(chan struct{})
	go func() {
		defer close(probeDone)
		_, _ = core.GetFullUser("12345")
	}()
	select {
	case <-probeDone:
	case <-time.After(2 * time.Second):
		t.Fatal("Logout: t.mu read lock starved while the logout RPC is in flight — write lock held across RPC (freeze class)")
	}
	select {
	case <-logoutDone:
		t.Fatal("Logout returned while its RPC is stuck on the scripted server")
	default:
	}
}

func tgStuckGetFullUser(t *testing.T, s *tgScriptedServer, core *TelegramCore) error {
	t.Helper()
	client, baseCtx, err := core.WithAPI()
	if err != nil {
		t.Fatalf("WithAPI: %v", err)
	}
	stuck := s.stickNext(tg.UsersGetFullUserRequestTypeID)
	t.Cleanup(func() { close(stuck.release) })
	_, err = client.UsersGetFullUser(baseCtx, &tg.InputUserSelf{})
	waitStuckEntered(t, stuck, "guarded UsersGetFullUser")
	return err
}

func TestRPCGuardBoundsHungRPC(t *testing.T) {
	old := RpcTimeout
	RpcTimeout = 100 * time.Millisecond
	defer func() { RpcTimeout = old }()

	s := newTGScriptedServer(t)
	core := s.authedCore(t)

	start := time.Now()
	err := tgStuckGetFullUser(t, s, core)
	if err == nil {
		t.Fatal("guarded invoke of a dead connection unexpectedly succeeded")
	}
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("guarded invoke error = %v, want context.DeadlineExceeded", err)
	}
	if elapsed := time.Since(start); elapsed > 5*time.Second {
		t.Fatalf("guarded invoke took %v — deadline not enforced", elapsed)
	}
}

func TestRPCGuardPreservesCallerDeadline(t *testing.T) {
	s := newTGScriptedServer(t)
	core := s.authedCore(t)
	client, baseCtx, err := core.WithAPI()
	if err != nil {
		t.Fatalf("WithAPI: %v", err)
	}
	deadline := time.Now().Add(50 * time.Millisecond)
	ctx, cancel := context.WithDeadline(baseCtx, deadline)
	defer cancel()

	stuck := s.stickNext(tg.UsersGetFullUserRequestTypeID)
	t.Cleanup(func() { close(stuck.release) })

	start := time.Now()
	_, _ = client.UsersGetFullUser(ctx, &tg.InputUserSelf{})
	waitStuckEntered(t, stuck, "caller-deadline UsersGetFullUser")
	if elapsed := time.Since(start); elapsed > 2*time.Second {
		t.Fatalf("invoke took %v — the guard overrode the caller's 50ms deadline with its 60s default", elapsed)
	}
}

func TestRPCGuardAppliesDefaultDeadline(t *testing.T) {
	old := RpcTimeout
	RpcTimeout = 250 * time.Millisecond
	defer func() { RpcTimeout = old }()

	s := newTGScriptedServer(t)
	core := s.authedCore(t)

	start := time.Now()
	err := tgStuckGetFullUser(t, s, core)
	if err == nil || !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("guarded invoke error = %v, want context.DeadlineExceeded", err)
	}
	if elapsed := time.Since(start); elapsed < 240*time.Millisecond {
		t.Fatalf("invoke returned after %v — the default deadline was not applied", elapsed)
	}
	if elapsed := time.Since(start); elapsed > 5*time.Second {
		t.Fatalf("invoke took %v — deadline not enforced", elapsed)
	}
}

func TestWithAPIRejectsUnauthed(t *testing.T) {
	core := NewTelegramCore(TelegramConfig{})
	if _, _, err := core.WithAPI(); err != ErrAuth {
		t.Fatalf("WithAPI on unauthed core = %v, want ErrAuth", err)
	}
}

func TestReadPathRPCsDoNotPinMutex(t *testing.T) {
	s := newTGScriptedServer(t)
	cases := []struct {
		what string
		rpc  uint32
		call func(tc *TelegramCore)
	}{
		{"GetInstalledEmojiSets", tg.MessagesGetEmojiStickersRequestTypeID, func(tc *TelegramCore) {
			_, _ = tc.GetInstalledEmojiSets()
		}},
		{"SetHideReadMarks", tg.AccountGetGlobalPrivacySettingsRequestTypeID, func(tc *TelegramCore) {
			_ = tc.SetHideReadMarks(true)
		}},
		{"GetCustomEmojiSetInfo", tg.MessagesGetCustomEmojiDocumentsRequestTypeID, func(tc *TelegramCore) {
			_, _, _, _, _, _, _ = tc.GetCustomEmojiSetInfo(1)
		}},
		{"GetContentSettings", tg.AccountGetContentSettingsRequestTypeID, func(tc *TelegramCore) {
			_, _, _, _ = tc.GetContentSettings()
		}},
		{"GetAvailableReactionEmojis", tg.MessagesGetTopReactionsRequestTypeID, func(tc *TelegramCore) {
			_, _ = tc.GetAvailableReactionEmojis()
		}},
		{"GetAllFolderLimits", tg.HelpGetAppConfigRequestTypeID, func(tc *TelegramCore) {
			_, _ = tc.GetAllFolderLimits()
		}},
		{"SetMessagesPrivacy", tg.AccountGetGlobalPrivacySettingsRequestTypeID, func(tc *TelegramCore) {
			_ = tc.SetMessagesPrivacy("everyone", 0)
		}},
		{"SetPersonalChannel", tg.ContactsResolveUsernameRequestTypeID, func(tc *TelegramCore) {
			_ = tc.SetPersonalChannel("@channel")
		}},
		{"GetDefaultBannedRights", tg.ChannelsGetChannelsRequestTypeID, func(tc *TelegramCore) {
			_, _ = tc.GetDefaultBannedRights("-1001234567890")
		}},
		{"AddChatToFolder", tg.MessagesGetDialogFiltersRequestTypeID, func(tc *TelegramCore) {
			_ = tc.AddChatToFolder("123", 2)
		}},
		{"GetParticipantsByRole", tg.ChannelsGetChannelsRequestTypeID, func(tc *TelegramCore) {
			_, _, _ = tc.GetParticipantsByRole("-1001234567890", "members", "", 10, 0)
		}},
		{"GetUserPhotoAtIndex", tg.PhotosGetUserPhotosRequestTypeID, func(tc *TelegramCore) {
			_, _, _ = tc.GetUserPhotoAtIndex("123", 0)
		}},
		{"SearchGlobalPostMessages", tg.ChannelsSearchPostsRequestTypeID, func(tc *TelegramCore) {
			_, _ = tc.SearchGlobalPostMessages("test", 5)
		}},
		{"CheckCloudPassword", tg.AccountGetPasswordRequestTypeID, func(tc *TelegramCore) {
			_ = tc.CheckCloudPassword("pw")
		}},
		{"SetCloudPassword", tg.AccountGetPasswordRequestTypeID, func(tc *TelegramCore) {
			_ = tc.SetCloudPassword("", "new", "hint", "")
		}},
		{"SetCloudPasswordEmail", tg.AccountGetPasswordRequestTypeID, func(tc *TelegramCore) {
			_ = tc.SetCloudPasswordEmail("", "a@b.c")
		}},
		{"RecoverPasswordWithCode", tg.AuthRecoverPasswordRequestTypeID, func(tc *TelegramCore) {
			_ = tc.RecoverPasswordWithCode("12345", "", "")
		}},
		{"TransferChannelOwnership", tg.AccountGetPasswordRequestTypeID, func(tc *TelegramCore) {
			_ = tc.TransferChannelOwnership("-1001234567890", "123", "pw")
		}},
		{"UploadProfilePhoto", tg.UploadSaveFilePartRequestTypeID, func(tc *TelegramCore) {
			_ = tc.UploadProfilePhoto([]byte{0x89, 'P', 'N', 'G'})
		}},
		{"SetBotPhoto", tg.UploadSaveFilePartRequestTypeID, func(tc *TelegramCore) {
			_ = tc.SetBotPhoto("123", []byte{0x89, 'P', 'N', 'G'})
		}},
		{"UploadFallbackPhoto", tg.UploadSaveFilePartRequestTypeID, func(tc *TelegramCore) {
			_ = tc.UploadFallbackPhoto([]byte{0x89, 'P', 'N', 'G'})
		}},
		{"DeleteFallbackPhoto", tg.UsersGetFullUserRequestTypeID, func(tc *TelegramCore) {
			_ = tc.DeleteFallbackPhoto()
		}},
		{"DeleteProfilePhotos", tg.PhotosGetUserPhotosRequestTypeID, func(tc *TelegramCore) {
			_ = tc.DeleteProfilePhotos()
		}},
		{"EditChannelPhoto", tg.ChannelsGetChannelsRequestTypeID, func(tc *TelegramCore) {
			_ = tc.EditChannelPhoto("-1001234567890", []byte{0x89, 'P', 'N', 'G'})
		}},
		{"EditChannelVideoPhoto", tg.ChannelsGetChannelsRequestTypeID, func(tc *TelegramCore) {
			_ = tc.EditChannelVideoPhoto("-1001234567890", []byte{0, 0, 0, 1})
		}},
		{"CreateCloudThemeWithData", tg.UploadSaveFilePartRequestTypeID, func(tc *TelegramCore) {
			_, _ = tc.CreateCloudThemeWithData("t", "s", []byte("theme"))
		}},
		{"UpdateCloudThemeWithData", tg.UploadSaveFilePartRequestTypeID, func(tc *TelegramCore) {
			_, _ = tc.UpdateCloudThemeWithData(1, 2, "t", "s", []byte("theme"))
		}},
		{"SendMediaAlbum", tg.UploadSaveFilePartRequestTypeID, func(tc *TelegramCore) {
			items := []AlbumItem{{Upload: FileUpload{Name: "a.png", MimeType: "image/png", Size: 4, Reader: bytes.NewReader([]byte{0x89, 'P', 'N', 'G'})}, IsPhoto: true}}
			_, _ = tc.SendMediaAlbum("123", items, false, 0)
		}},
		{"SendImageBase64", tg.UploadSaveFilePartRequestTypeID, func(tc *TelegramCore) {
			_, _ = tc.SendImageBase64("123", "aVBORw==", "cap")
		}},
		{"GetDifferenceCheck", tg.UpdatesGetStateRequestTypeID, func(tc *TelegramCore) {
			_ = tc.GetDifferenceCheck()
		}},
		{"DownloadWallpaperDocument", tg.UploadGetFileRequestTypeID, func(tc *TelegramCore) {
			_, _ = tc.DownloadWallpaperDocument(1, 2, []byte("ref"))
		}},
		{"UploadFile", tg.UploadSaveFilePartRequestTypeID, func(tc *TelegramCore) {
			_, _ = tc.UploadFile("123", FileUpload{Name: "f.png", MimeType: "image/png", Size: 4, Reader: bytes.NewReader([]byte{0x89, 'P', 'N', 'G'})}, nil)
		}},
		{"UploadFileWithOptions", tg.UploadSaveFilePartRequestTypeID, func(tc *TelegramCore) {
			_, _ = tc.UploadFileWithOptions("123", FileUpload{Name: "f.png", MimeType: "image/png", Size: 4, Reader: bytes.NewReader([]byte{0x89, 'P', 'N', 'G'})}, UploadOptions{}, nil)
		}},
		{"SendStoryWithPhoto", tg.UploadSaveFilePartRequestTypeID, func(tc *TelegramCore) {
			_, _ = tc.SendStoryWithPhoto("cap", []byte{0x89, 'P', 'N', 'G'}, StoryPostOptions{})
		}},
		{"SendStoryWithVideoFile", tg.UploadSaveFilePartRequestTypeID, func(tc *TelegramCore) {
			tmp := filepath.Join(os.TempDir(), "freeze_story.mp4")
			if err := os.WriteFile(tmp, []byte("\x00\x00\x00\x18ftypmp42"), 0o600); err != nil {
				t.Fatal(err)
			}
			_, _ = tc.SendStoryWithVideoFile("cap", tmp, StoryPostOptions{})
		}},
	}
	for _, tc := range cases {
		t.Run(tc.what, func(t *testing.T) {
			core := s.authedCore(t)
			stuck := s.stickNext(tc.rpc)
			t.Cleanup(func() { close(stuck.release) })
			go func() {
				defer func() { _ = recover() }()
				tc.call(core)
			}()
			waitStuckEntered(t, stuck, tc.what)
			probe := s.watchType(tg.AuthLogOutRequestTypeID)
			go func() { _ = core.Logout() }()
			waitWatched(t, probe, tc.what+": Logout write-lock probe")
		})
	}
}
