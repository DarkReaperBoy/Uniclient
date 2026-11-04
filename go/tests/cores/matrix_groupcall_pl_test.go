package tests

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	. "uniclient/cores"

	"github.com/pion/webrtc/v4"
	"maunium.net/go/mautrix/id"
)

type createRoomCapture struct {
	Body string
}

func newCreateRoomServer(t *testing.T) (*httptest.Server, *createRoomCapture) {
	t.Helper()
	cap := &createRoomCapture{}
	srv := httptest.NewServer(mxAuthSurface(id.UserID("@alice:localhost"), id.DeviceID("DEV1"), http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/createRoom") && r.Method == http.MethodPost {
			b, _ := io.ReadAll(r.Body)
			cap.Body = string(b)
			w.Header().Set("Content-Type", "application/json")
			_, _ = io.WriteString(w, `{"room_id":"!created:localhost"}`)
			return
		}
		w.WriteHeader(http.StatusNotFound)
		_, _ = io.WriteString(w, `{"errcode":"M_NOT_FOUND"}`)
	})))
	t.Cleanup(srv.Close)
	return srv, cap
}

func newCreateRoomTestCore(t *testing.T, srvURL string) *MatrixCore {
	t.Helper()
	core := NewMatrixCore(nil)
	t.Cleanup(func() { _ = core.Close() })
	if err := core.Authenticate(AuthConfig{
		Mode:     AuthModeBot,
		BotToken: "tok",
		Extra:    map[string]string{"homeserver": srvURL},
	}); err != nil {
		t.Fatalf("authenticate: %v", err)
	}
	return core
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
