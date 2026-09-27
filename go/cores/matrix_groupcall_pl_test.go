package cores

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/pion/webrtc/v4"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/id"
)

// B-6 → F-62: rooms WE create must grant the MSC3401 event types at
// PL 0, or any non-creator member (PL 0 < state_default 50) cannot
// publish their m.call.member state event — exactly the live-dendrite
// failure (`M_FORBIDDEN ... 0 < 50` on bob's membership publish).
// Reference implementations do the same at createRoom time
// (matrix-dart-sdk: powerLevelContentOverride.events = {call.member:
// 0, call: 0}).
//
// Seam-RED (WORKLOG 300): CreateGroup currently sends NO
// power_level_content_override at all.

type createRoomCapture struct {
	Body string
}

// newCreateRoomServer answers ONLY POST /createRoom and captures it.
func newCreateRoomServer(t *testing.T) (*httptest.Server, *createRoomCapture) {
	t.Helper()
	cap := &createRoomCapture{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/createRoom") && r.Method == http.MethodPost {
			b, _ := io.ReadAll(r.Body)
			cap.Body = string(b)
			w.Header().Set("Content-Type", "application/json")
			_, _ = io.WriteString(w, `{"room_id":"!created:localhost"}`)
			return
		}
		w.WriteHeader(http.StatusNotFound)
		_, _ = io.WriteString(w, `{"errcode":"M_NOT_FOUND"}`)
	}))
	t.Cleanup(srv.Close)
	return srv, cap
}

func newCreateRoomTestCore(t *testing.T, srvURL string) *MatrixCore {
	t.Helper()
	client, err := mautrix.NewClient(srvURL, id.UserID("@alice:localhost"), "tok")
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	return &MatrixCore{
		authed:     true,
		ctx:        context.Background(),
		deviceID:   "DEV1",
		userID:     id.UserID("@alice:localhost"),
		homeserver: srvURL,
		client:     client,
	}
}

func TestCreateGroupGrantsMSC3401PowerLevels(t *testing.T) {
	srv, cap := newCreateRoomServer(t)
	core := newCreateRoomTestCore(t, srv.URL)

	if _, err := core.CreateGroup("call room", []string{"@bob:localhost"}); err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}
	if cap.Body == "" {
		t.Fatal("createRoom was never called")
	}

	var body struct {
		PLE struct {
			Events map[string]int `json:"events"`
		} `json:"power_level_content_override"`
	}
	if err := json.Unmarshal([]byte(cap.Body), &body); err != nil {
		t.Fatalf("createRoom body %q: %v", cap.Body, err)
	}
	ev := body.PLE.Events
	if v, ok := ev["org.matrix.msc3401.call.member"]; !ok || v != 0 {
		t.Errorf("power_level_content_override missing call.member=0: %v", ev)
	}
	if v, ok := ev["org.matrix.msc3401.call"]; !ok || v != 0 {
		t.Errorf("power_level_content_override missing call=0: %v", ev)
	}
	// The override must NOT drop server defaults (shallow-merge servers
	// replace the whole events map — providing only our keys would
	// silently drop m.room.power_levels:100 etc).
	if v := ev["m.room.power_levels"]; v != 100 {
		t.Errorf("default m.room.power_levels not preserved: %v", ev)
	}
	if v := ev["m.room.name"]; v != 50 {
		t.Errorf("default m.room.name not preserved: %v", ev)
	}
}

func TestCreateChannelGrantsMSC3401PowerLevels(t *testing.T) {
	srv, cap := newCreateRoomServer(t)
	core := newCreateRoomTestCore(t, srv.URL)

	if _, err := core.CreateChannel("call channel", "d"); err != nil {
		t.Fatalf("CreateChannel: %v", err)
	}
	if cap.Body == "" {
		t.Fatal("createRoom was never called")
	}
	var body struct {
		PLE struct {
			Events map[string]int `json:"events"`
		} `json:"power_level_content_override"`
	}
	if err := json.Unmarshal([]byte(cap.Body), &body); err != nil {
		t.Fatalf("createRoom body %q: %v", cap.Body, err)
	}
	if v, ok := body.PLE.Events["org.matrix.msc3401.call.member"]; !ok || v != 0 {
		t.Errorf("channel missing call.member=0: %v", body.PLE.Events)
	}
	if v, ok := body.PLE.Events["org.matrix.msc3401.call"]; !ok || v != 0 {
		t.Errorf("channel missing call=0: %v", body.PLE.Events)
	}
}

var _ = webrtc.MimeTypeOpus
