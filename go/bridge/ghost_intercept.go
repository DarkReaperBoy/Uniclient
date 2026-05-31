package bridge

import (
	"google.golang.org/protobuf/proto"

	pbcores "uniclient/proto/cores"
)

// ghostIntercept checks ghost mode settings and suppresses API calls
// that should be blocked. Returns true if the call was suppressed.
// accountID is the core_id of the call's target account, so ghost flags
// resolve per-account (AyuGram resolves ghost per session/userId).
func ghostIntercept(method string, payload []byte, entry coreEntry, accountID string) bool {
	if engineInstance == nil {
		return false
	}
	// SendTyping is a global (not per-account) ghost setting; the rest resolve
	// per-account so background accounts enforce their own ghost profile.
	g := engineInstance.GhostFor(accountID)

	switch method {
	case "SendTyping":
		return !engineInstance.GetConfig().SendTyping

	case "UpdateStatus":
		if !g.SendOnlinePackets {
			var req pbcores.TelegramUpdateStatusRequest
			if err := proto.Unmarshal(payload, &req); err == nil && req.Online {
				return true
			}
		}
		if g.SendOfflineAfterOnline {
			var req pbcores.TelegramUpdateStatusRequest
			if err := proto.Unmarshal(payload, &req); err == nil && req.Online {
				go ghostSendOffline(entry)
			}
		}

	case "StoriesReadStories":
		return !g.SendReadStories

	case "StoriesIncrementStoryViews":
		return !g.SendReadStories
	}

	return false
}

// ghostSendOffline immediately sends an offline status update after
// going online (AyuGram "go offline automatically" feature).
func ghostSendOffline(entry coreEntry) {
	type statusUpdater interface {
		UpdateStatus(online bool) error
	}
	if su, ok := entry.instance.(statusUpdater); ok {
		su.UpdateStatus(false)
	}
}
