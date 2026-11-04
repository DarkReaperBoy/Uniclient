package tests

import (
	"encoding/json"
	"reflect"
	"testing"
	"time"
	. "uniclient/cores"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

var (
	_ VoiceCore = (*MatrixCore)(nil)
	_ interface {
		GetGroupCall(chatID string) (*CallSession, error)
	} = (*MatrixCore)(nil)
)

type meshRelay struct {
	from   *meshPuts
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
					to.HandleCallInvite(&event.Event{
						Type: event.CallInvite, RoomID: room, Sender: r.sender,
						Content: event.Content{VeryRaw: json.RawMessage(p.Body)},
					})
				case event.CallAnswer.Type:
					to.HandleCallAnswer(&event.Event{
						Type: event.CallAnswer, RoomID: room, Sender: r.sender,
						Content: event.Content{VeryRaw: json.RawMessage(p.Body)},
					})
				case event.CallCandidates.Type:
					to.HandleCallCandidates(&event.Event{
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
	srvB, putsB := newMeshHomeserverAs(t, id.UserID("@alice:test"), id.DeviceID("DEV2"))
	a = newMeshTestCore(t, srvA.URL)
	b = newMeshTestCore(t, srvB.URL)

	const conf = "conf_loop"
	srvA.setCallConf(conf)
	srvB.setCallConf(conf)
	for _, c := range []*MatrixCore{a, b} {
		fireGroupMemberEvent(t, c, "@alice:test", MatrixCallMemberContent{Calls: []MatrixCallMemberCall{{
			CallID: conf,
			Devices: []MatrixCallDevice{{
				DeviceID: "DEV1", SessionID: "sa",
				ExpiresTS: time.Now().UnixMilli() + 60_000,
			}},
		}}})
		fireGroupMemberEvent(t, c, "@bob:test", MatrixCallMemberContent{Calls: []MatrixCallMemberCall{{
			CallID: conf,
			Devices: []MatrixCallDevice{{
				DeviceID: "DEV2", SessionID: "sb",
				ExpiresTS: time.Now().UnixMilli() + 60_000,
			}},
		}}})
		sess, err := c.JoinGroupCall("!room:test")
		if err != nil {
			t.Fatalf("join group call: %v", err)
		}
		if sess.ID != conf {
			t.Fatalf("conf = %q, want %s (adopted from server call state)", sess.ID, conf)
		}
	}
	startMeshRelay(t, putsA, id.UserID("@alice:test"), b)
	startMeshRelay(t, putsB, id.UserID("@bob:test"), a)
	return a, b
}

func TestMeshAudioLoopback(t *testing.T) {
	a, b := seedJoinedPair(t)

	received := make(chan []byte, 16)
	b.OnVoiceFrame(func(sender string, opus []byte) {
		if sender == "@alice:test" {
			received <- append([]byte{}, opus...)
		}
	})

	if err := a.ReconcileGroupMesh(); err != nil {
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

func TestMeshVoiceMuteStopsFrames(t *testing.T) {
	a, b := seedJoinedPair(t)
	received := make(chan []byte, 8)
	b.OnVoiceFrame(func(sender string, opus []byte) {
		if sender == "@alice:test" {
			received <- append([]byte{}, opus...)
		}
	})
	if err := a.ReconcileGroupMesh(); err != nil {
		t.Fatalf("A reconcile: %v", err)
	}

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
				return
			}
		case <-time.After(150 * time.Millisecond):
		}
	}
	t.Fatal("no frame after unmute")
}

func TestMatrixGetGroupCall(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := newMeshTestCore(t, srv.URL)

	if cs, err := core.GetGroupCall("!room:test"); err != nil || cs != nil {
		t.Fatalf("not joined: cs=%v err=%v, want (nil, nil)", cs, err)
	}

	fireGroupMemberEvent(t, core, "@alice:test", MatrixCallMemberContent{Calls: []MatrixCallMemberCall{{
		CallID:  "conf_x",
		Devices: []MatrixCallDevice{{DeviceID: "DEV1", ExpiresTS: time.Now().UnixMilli() + 60_000}},
	}}})
	fireGroupMemberEvent(t, core, "@bob:test", MatrixCallMemberContent{Calls: []MatrixCallMemberCall{{
		CallID:  "conf_x",
		Devices: []MatrixCallDevice{{DeviceID: "DEV2", ExpiresTS: time.Now().UnixMilli() + 60_000}},
	}}})
	fireGroupMemberEvent(t, core, "@carol:test", MatrixCallMemberContent{Calls: []MatrixCallMemberCall{{
		CallID:  "conf_x",
		Devices: []MatrixCallDevice{{DeviceID: "C1", ExpiresTS: time.Now().UnixMilli() - 1}},
	}}})
	srv.setCallConf("conf_x")
	sess, err := core.JoinGroupCall("!room:test")
	if err != nil {
		t.Fatalf("join group call: %v", err)
	}
	if sess.ID != "conf_x" {
		t.Fatalf("conf = %q, want conf_x (adopted from server call state)", sess.ID)
	}

	cs, err := core.GetGroupCall("!room:test")
	if err != nil {
		t.Fatalf("GetGroupCall: %v", err)
	}
	if cs == nil || !cs.IsGroup || cs.State != CallStateActive || cs.ID != "conf_x" {
		t.Fatalf("session = %+v", cs)
	}
	if cs.Meta["participants_count"] != "2" {
		t.Fatalf("participants_count = %q, want 2 (expired filtered)", cs.Meta["participants_count"])
	}
	if len(cs.Participants) != 2 {
		t.Fatalf("participants = %+v", cs.Participants)
	}

	if cs, err := core.GetGroupCall("!other:test"); err != nil || cs != nil {
		t.Fatalf("wrong room: cs=%v err=%v", cs, err)
	}
}
