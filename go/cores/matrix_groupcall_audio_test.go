package cores

import (
	"encoding/json"
	"reflect"
	"testing"
	"time"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

// B-6 → F-62, slice 298: mesh AUDIO + engine surface.
//
// Compile-time truth for the engine's RUNTIME type assertions
// (engine/cache_chats.go: `acc.Core.(groupCaller)` and
// `acc.Core.(cores.VoiceCore)`): if either method ever drifts, the
// join flow would silently stop starting the voice pipeline or the
// group bar — this line turns that into a build failure.
var (
	_ VoiceCore = (*MatrixCore)(nil)
	_ interface {
		GetGroupCall(chatID string) (*CallSession, error)
	} = (*MatrixCore)(nil)
)

//
// The loopback test is the milestone: two MatrixCores, two scripted
// homeservers, a manual event relay (no sync loop) — a real pion mesh
// forms on host candidates and A.SendVoiceFrame must arrive at
// B.OnVoiceFrame tagged with A's MXID.
//
// Seam-RED (WORKLOG 298): undefined: core.SendVoiceFrame / GetGroupCall.

// meshRelay pumps PUTs from one core's mini-server into the other
// core's handlers, tagging the sender.
type meshRelay struct {
	from   *meshPuts // race-safe snapshot store
	sender id.UserID
	to     *MatrixCore
	stop   chan struct{}
	cursor int
}

func startMeshRelay(t *testing.T, puts *meshPuts, sender id.UserID, to *MatrixCore) {
	t.Helper()
	r := &meshRelay{from: puts, sender: sender, to: to, stop: make(chan struct{})}
	t.Cleanup(func() { close(r.stop) })
	go func() {
		for {
			select {
			case <-r.stop:
				return
			case <-time.After(20 * time.Millisecond):
			}
			for {
				events := r.from.snapshot()
				if r.cursor >= len(events) {
					break
				}
				p := events[r.cursor]
				r.cursor++
				room := id.RoomID("!room:test")
				switch p.Type {
				case event.CallInvite.Type:
					to.handleCallInvite(&event.Event{
						Type: event.CallInvite, RoomID: room, Sender: r.sender,
						Content: event.Content{VeryRaw: json.RawMessage(p.Body)},
					})
				case event.CallAnswer.Type:
					to.handleCallAnswer(&event.Event{
						Type: event.CallAnswer, RoomID: room, Sender: r.sender,
						Content: event.Content{VeryRaw: json.RawMessage(p.Body)},
					})
				case event.CallCandidates.Type:
					to.handleCallCandidates(&event.Event{
						Type: event.CallCandidates, RoomID: room, Sender: r.sender,
						Content: event.Content{VeryRaw: json.RawMessage(p.Body)},
					})
				}
			}
		}
	}()
}

func seedJoinedPair(t *testing.T) (a, b *MatrixCore) {
	t.Helper()
	srvA, putsA := newMeshHomeserver(t)
	srvB, putsB := newMeshHomeserver(t)
	a = newMeshTestCore(t, srvA.URL)
	b = newMeshTestCore(t, srvB.URL)
	b.deviceID = "DEV2" // second device for distinct peer keys

	const conf = "conf_loop"
	for _, c := range []*MatrixCore{a, b} {
		c.groupConfID = conf
		c.groupRoomID = "!room:test"
		c.groupSession = "s-" + c.deviceID.String()
		c.groupMembers = map[id.UserID]matrixCallMemberContent{
			id.UserID("@alice:test"): {Calls: []matrixCallMemberCall{{
				CallID: conf,
				Devices: []matrixCallDevice{{
					DeviceID: "DEV1", SessionID: "sa",
					ExpiresTS: time.Now().UnixMilli() + 60_000,
				}},
			}}},
			id.UserID("@bob:test"): {Calls: []matrixCallMemberCall{{
				CallID: conf,
				Devices: []matrixCallDevice{{
					DeviceID: "DEV2", SessionID: "sb",
					ExpiresTS: time.Now().UnixMilli() + 60_000,
				}},
			}}},
		}
	}
	startMeshRelay(t, putsA, id.UserID("@alice:test"), b)
	startMeshRelay(t, putsB, id.UserID("@bob:test"), a)
	return a, b
}

// TestMeshAudioLoopback: A offers (alice < bob), the relay carries
// invite/answer/candidates both ways, ICE connects on host candidates,
// then a driven frame must land on B's OnVoiceFrame with A's MXID as
// the sender.
func TestMeshAudioLoopback(t *testing.T) {
	a, b := seedJoinedPair(t)

	received := make(chan []byte, 16)
	b.OnVoiceFrame(func(sender string, opus []byte) {
		if sender == "@alice:test" {
			received <- append([]byte{}, opus...)
		}
	})

	if err := a.reconcileGroupMesh(); err != nil {
		t.Fatalf("A reconcile: %v", err)
	}

	frame := []byte{0xf8, 0xff, 0xfe, 0x11, 0x22}
	deadline := time.Now().Add(12 * time.Second)
	got := false
	for time.Now().Before(deadline) && !got {
		_ = a.SendVoiceFrame(frame)
		select {
		case gotFrame := <-received:
			if reflect.DeepEqual(gotFrame, frame) {
				got = true
			}
		case <-time.After(150 * time.Millisecond):
		}
	}
	if !got {
		t.Fatal("no audio crossed the mesh: B never received A's frame")
	}
}

// TestMeshVoiceMuteStopsFrames: muting drops outgoing frames, unmuting
// restores them (the flag must actually flip, not just drop once).
func TestMeshVoiceMuteStopsFrames(t *testing.T) {
	a, b := seedJoinedPair(t)
	received := make(chan []byte, 8)
	b.OnVoiceFrame(func(sender string, opus []byte) {
		if sender == "@alice:test" {
			received <- append([]byte{}, opus...)
		}
	})
	if err := a.reconcileGroupMesh(); err != nil {
		t.Fatalf("A reconcile: %v", err)
	}

	// Wait for the connection first (unmuted).
	connectDeadline := time.Now().Add(12 * time.Second)
	connected := false
	for time.Now().Before(connectDeadline) && !connected {
		_ = a.SendVoiceFrame([]byte{0xf8, 0xff, 0xfe})
		select {
		case <-received:
			connected = true
		case <-time.After(150 * time.Millisecond):
		}
	}
	if !connected {
		t.Fatal("mesh never connected")
	}

	if err := a.SetVoiceMuted(true); err != nil {
		t.Fatalf("mute: %v", err)
	}
	for i := 0; i < 20; i++ {
		_ = a.SendVoiceFrame([]byte{0xde, 0xad})
	}
	select {
	case <-received:
		t.Fatal("frame delivered while muted")
	case <-time.After(300 * time.Millisecond):
	}

	if err := a.SetVoiceMuted(false); err != nil {
		t.Fatalf("unmute: %v", err)
	}
	unmuteDeadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(unmuteDeadline) {
		_ = a.SendVoiceFrame([]byte{0xbe, 0xef})
		select {
		case f := <-received:
			if reflect.DeepEqual(f, []byte{0xbe, 0xef}) {
				return // GREEN
			}
		case <-time.After(150 * time.Millisecond):
		}
	}
	t.Fatal("no frame after unmute")
}

// TestMatrixGetGroupCall: the engine's groupCaller contract — joined →
// an ACTIVE IsGroup session with participants; not joined → (nil, nil).
func TestMatrixGetGroupCall(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := newMeshTestCore(t, srv.URL)

	if cs, err := core.GetGroupCall("!room:test"); err != nil || cs != nil {
		t.Fatalf("not joined: cs=%v err=%v, want (nil, nil)", cs, err)
	}

	core.groupConfID = "conf_x"
	core.groupRoomID = "!room:test"
	core.groupMembers = map[id.UserID]matrixCallMemberContent{
		"@alice:test": {Calls: []matrixCallMemberCall{{
			CallID:  "conf_x",
			Devices: []matrixCallDevice{{DeviceID: "DEV1", ExpiresTS: time.Now().UnixMilli() + 60_000}},
		}}},
		"@bob:test": {Calls: []matrixCallMemberCall{{
			CallID:  "conf_x",
			Devices: []matrixCallDevice{{DeviceID: "DEV2", ExpiresTS: time.Now().UnixMilli() + 60_000}},
		}}},
		"@carol:test": {Calls: []matrixCallMemberCall{{
			CallID:  "conf_x",
			Devices: []matrixCallDevice{{DeviceID: "C1", ExpiresTS: time.Now().UnixMilli() - 1}},
		}}},
	}

	cs, err := core.GetGroupCall("!room:test")
	if err != nil {
		t.Fatalf("GetGroupCall: %v", err)
	}
	if cs == nil || !cs.IsGroup || cs.State != CallStateActive || cs.ID != "conf_x" {
		t.Fatalf("session = %+v", cs)
	}
	if cs.Meta["participants_count"] != "2" { // alice+bob live, carol expired
		t.Fatalf("participants_count = %q, want 2 (expired filtered)", cs.Meta["participants_count"])
	}
	if len(cs.Participants) != 2 {
		t.Fatalf("participants = %+v", cs.Participants)
	}

	// Wrong room → no call.
	if cs, err := core.GetGroupCall("!other:test"); err != nil || cs != nil {
		t.Fatalf("wrong room: cs=%v err=%v", cs, err)
	}
}
