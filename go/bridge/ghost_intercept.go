package bridge

import (
	"google.golang.org/protobuf/proto"

	pbcores "uniclient/proto/cores"
)

// ghostIntercept checks ghost mode settings and suppresses API calls
// that should be blocked. Returns true if the call was suppressed.
func ghostIntercept(method string, payload []byte, entry coreEntry) bool {
	if engineInstance == nil {
		return false
	}
	cfg := engineInstance.GetConfig()

	switch method {
	case "SendTyping":
		return !cfg.SendTyping

	case "UpdateStatus":
		if !cfg.SendOnlinePackets {
			var req pbcores.TelegramUpdateStatusRequest
			if err := proto.Unmarshal(payload, &req); err == nil && req.Online {
				return true
			}
		}
		if cfg.SendOfflineAfterOnline {
			var req pbcores.TelegramUpdateStatusRequest
			if err := proto.Unmarshal(payload, &req); err == nil && req.Online {
				go ghostSendOffline(entry)
			}
		}

	case "StoriesReadStories":
		return !cfg.SendReadStories

	case "StoriesIncrementStoryViews":
		return !cfg.SendReadStories
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
