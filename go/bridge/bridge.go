// Package bridge provides the FFI entry point for the uniclient protobuf bridge.
//
// Flutter/Dart calls BridgeCall with a serialized BridgeRequest proto.
// Go dispatches to the appropriate core + method and returns a serialized BridgeResponse.
// Async events (updates) are pushed to Dart via a callback port set by BridgeSetEventPort.
package bridge

import (
	"fmt"
	"os"
	"strconv"
	"sync"

	"github.com/gotd/td/session"
	"google.golang.org/protobuf/proto"

	"uniclient/cores"
	"uniclient/engine"
	pb "uniclient/proto"
)

// coreRegistry maps core_id → (core instance, core type name).
var (
	mu    sync.RWMutex
	registry = make(map[string]coreEntry)

	// eventCallback is called when an async event (update) fires.
	// Set via SetEventCallback from the FFI layer.
	eventCallback func([]byte)
)

type coreEntry struct {
	instance interface{}
	coreType string // "telegram", "bale", etc.
}

// RegisterCore registers a core instance for bridge dispatch.
// coreID is an arbitrary identifier (e.g. "tg-main"), coreType is the platform
// name matching dispatch (e.g. "telegram"), and instance is the *XxxCore pointer.
func RegisterCore(coreID, coreType string, instance interface{}) {
	mu.Lock()
	defer mu.Unlock()
	registry[coreID] = coreEntry{instance: instance, coreType: coreType}
}

// UnregisterCore removes a core from the bridge.
func UnregisterCore(coreID string) {
	mu.Lock()
	defer mu.Unlock()
	delete(registry, coreID)
}

// SetEventCallback sets the function called when async events are pushed to Dart.
// The callback receives serialized BridgeEvent proto bytes.
func SetEventCallback(cb func([]byte)) {
	mu.Lock()
	defer mu.Unlock()
	eventCallback = cb
}

// PushEvent sends an async event to the Dart side.
func PushEvent(event *pb.BridgeEvent) {
	mu.RLock()
	cb := eventCallback
	mu.RUnlock()
	if cb == nil {
		return
	}
	data, err := proto.Marshal(event)
	if err != nil {
		return
	}
	cb(data)
}

// Call processes a serialized BridgeRequest and returns a serialized BridgeResponse.
// This is the main dispatch function — the FFI layer wraps this.
func Call(reqData []byte) []byte {
	var req pb.BridgeRequest
	if err := proto.Unmarshal(reqData, &req); err != nil {
		return marshalError("invalid request: " + err.Error())
	}

	// Engine dispatch — core_id "__engine" routes to the engine layer.
	if req.CoreId == "__engine" {
		respPayload, err := dispatchEngine(req.Method, req.Payload)
		if err != nil {
			return marshalErrorCategorized(err)
		}
		resp := &pb.BridgeResponse{
			Ok:      true,
			Payload: respPayload,
		}
		data, err := proto.Marshal(resp)
		if err != nil {
			return marshalError("marshal response: " + err.Error())
		}
		return data
	}

	mu.RLock()
	entry, ok := registry[req.CoreId]
	mu.RUnlock()
	if !ok {
		return marshalError("unknown core_id: " + req.CoreId)
	}

	respPayload, err := Dispatch(entry.instance, entry.coreType, req.Method, req.Payload)
	if err != nil {
		return marshalErrorCategorized(err)
	}

	resp := &pb.BridgeResponse{
		Ok:      true,
		Payload: respPayload,
	}
	data, err := proto.Marshal(resp)
	if err != nil {
		return marshalError("marshal response: " + err.Error())
	}
	return data
}

// InitEngine initializes the engine and wires its event callback into the bridge.
// Call this from the FFI Init handler before any other engine operations.
func InitEngine(configDir, cacheDir, downloadDir, vaultPassword string) error {
	// Register core factory so the engine can create platform instances.
	// Each account gets its own session file under configDir/sessions/<platform>/<accountID>.json.
	engine.SetCoreFactory(func(platform, accountID string) (cores.Core, error) {
		sessionDir := configDir + "/sessions/" + platform
		if err := os.MkdirAll(sessionDir, 0o755); err != nil {
			return nil, fmt.Errorf("create session dir: %w", err)
		}
		switch platform {
		case "telegram":
			// Read API credentials from env or use defaults.
			apiID := 2040
			apiHash := "b18441a1ff607e10a989891a5462e627"
			if v := os.Getenv("TG_API_ID"); v != "" {
				if id, err := strconv.Atoi(v); err == nil {
					apiID = id
				}
			}
			if v := os.Getenv("TG_API_HASH"); v != "" {
				apiHash = v
			}
			sessionPath := sessionDir + "/" + accountID + ".json"
			return cores.NewTelegramCore(cores.TelegramConfig{
				APIID:          apiID,
				APIHash:        apiHash,
				SessionStorage: &session.FileStorage{Path: sessionPath},
			}), nil
		case "bale":
			return cores.NewBaleCore(sessionDir), nil
		case "matrix":
			return cores.NewMatrixCore(sessionDir), nil
		case "irc":
			return cores.NewIRCCore(sessionDir), nil
		case "xmpp":
			return cores.NewXMPPCore(sessionDir), nil
		case "github":
			return cores.NewGitHubCore(sessionDir), nil
		case "rubika":
			return cores.NewRubikaCore(sessionDir), nil
		case "deltachat":
			return cores.NewDeltaChatCore(sessionDir), nil
		case "teamspeak":
			return cores.NewTeamSpeakCore(sessionDir), nil
		case "mumble":
			return &cores.MumbleCore{}, nil
		default:
			return nil, fmt.Errorf("unknown platform: %s", platform)
		}
	})

	eng, err := engine.Init(configDir, cacheDir, downloadDir, vaultPassword)
	if err != nil {
		return err
	}
	SetEngine(eng)

	// Wire engine events through the bridge event system.
	// Engine emits JSON-encoded EngineEvent bytes; we wrap them in BridgeEvent.
	eng.SetEventCallback(func(data []byte) {
		event := &pb.BridgeEvent{
			CoreId:      "__engine",
			EngineEvent: data,
		}
		PushEvent(event)
	})

	return nil
}

// marshalError returns a serialized BridgeResponse with the given error message.
func marshalError(msg string) []byte {
	resp := &pb.BridgeResponse{
		Ok:    false,
		Error: msg,
	}
	data, err := proto.Marshal(resp)
	if err != nil {
		// Last resort: return minimal valid protobuf for error
		return []byte{0x10, 0x00}
	}
	return data
}

// marshalErrorCategorized returns a serialized BridgeResponse with error categorization.
func marshalErrorCategorized(err error) []byte {
	resp := &pb.BridgeResponse{
		Ok:        false,
		Error:     err.Error(),
		ErrorCode: categorizeError(err),
	}
	data, merr := proto.Marshal(resp)
	if merr != nil {
		return []byte{0x10, 0x00}
	}
	return data
}

// categorizeError maps Go errors to sentinel categories for the GUI.
func categorizeError(err error) string {
	if err == nil {
		return ""
	}
	msg := err.Error()

	// Check for known sentinel errors
	switch {
	case contains(msg, "auth", "unauthorized", "FLOOD_WAIT", "SESSION_EXPIRED", "AUTH_KEY"):
		return "auth"
	case contains(msg, "timeout", "deadline", "context deadline"):
		return "timeout"
	case contains(msg, "network", "connection", "dial", "EOF", "reset by peer", "broken pipe"):
		return "network"
	case contains(msg, "not found", "NOT_FOUND", "404", "no such"):
		return "not_found"
	case contains(msg, "rate limit", "FLOOD", "429", "too many requests", "slowmode"):
		return "rate_limited"
	case contains(msg, "permission", "forbidden", "403", "CHAT_ADMIN_REQUIRED", "not allowed"):
		return "permission"
	case contains(msg, "not supported", "not implemented", "501"):
		return "not_supported"
	}
	return "unknown"
}

// contains checks if s contains any of the substrings (case-insensitive-ish).
func contains(s string, subs ...string) bool {
	for _, sub := range subs {
		if len(sub) <= len(s) {
			for i := 0; i <= len(s)-len(sub); i++ {
				match := true
				for j := 0; j < len(sub); j++ {
					a, b := s[i+j], sub[j]
					if a != b && a != b+32 && a != b-32 {
						match = false
						break
					}
				}
				if match {
					return true
				}
			}
		}
	}
	return false
}
