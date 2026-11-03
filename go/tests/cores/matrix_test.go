package tests

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
	. "uniclient/cores"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

func newTestMatrix() *MatrixCore {
	m := NewMatrixCore(nil)
	m.ForTestSetUserID(id.UserID("@me:test"))
	return m
}

func mxJourneyServer(t *testing.T) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/_matrix/client/v3/account/whoami":
			if r.Header.Get("Authorization") != "Bearer test-token" {
				w.WriteHeader(http.StatusUnauthorized)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"user_id":"@me:test","device_id":"TESTDEV"}`))
		case "/_matrix/client/v3/keys/query":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"device_keys":{}}`))
		case "/_matrix/client/v3/keys/upload":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"one_time_key_counts":{}}`))
		case "/_matrix/client/v3/sync":
			<-r.Context().Done()
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	return srv
}

func mxAuthedCore(t *testing.T) *MatrixCore {
	srv := mxJourneyServer(t)
	m := NewMatrixCore(nil)
	t.Cleanup(func() { _ = m.Close() })
	if err := m.Authenticate(AuthConfig{
		Mode:     AuthModeBot,
		BotToken: "test-token",
		Extra:    map[string]string{"homeserver": srv.URL},
	}); err != nil {
		t.Fatalf("authenticate: %v", err)
	}
	return m
}

func mxRunCaptured(t *testing.T, fn func()) (stdout, stderr string) {
	t.Helper()
	or, ow, err := os.Pipe()
	if err != nil {
		t.Fatalf("stdout pipe: %v", err)
	}
	er, ew, err := os.Pipe()
	if err != nil {
		t.Fatalf("stderr pipe: %v", err)
	}
	oldOut, oldErr := os.Stdout, os.Stderr
	os.Stdout, os.Stderr = ow, ew
	var outBuf, errBuf bytes.Buffer
	drained := make(chan struct{})
	go func() { _, _ = io.Copy(&outBuf, or); drained <- struct{}{} }()
	go func() { _, _ = io.Copy(&errBuf, er); drained <- struct{}{} }()
	defer func() {
		os.Stdout, os.Stderr = oldOut, oldErr
		_ = ow.Close()
		_ = ew.Close()
	}()
	fn()
	os.Stdout, os.Stderr = oldOut, oldErr
	_ = ow.Close()
	_ = ew.Close()
	<-drained
	<-drained
	_ = or.Close()
	_ = er.Close()
	return outBuf.String(), errBuf.String()
}

func mxAuthJourneyCaptured(t *testing.T, srv *httptest.Server) (stdout, stderr string, authErr error) {
	t.Helper()
	stdout, stderr = mxRunCaptured(t, func() {
		m := NewMatrixCore(nil)
		defer func() { _ = m.Close() }()
		authErr = m.Authenticate(AuthConfig{
			Mode:     AuthModeBot,
			BotToken: "test-token",
			Extra:    map[string]string{"homeserver": srv.URL},
		})
	})
	return stdout, stderr, authErr
}

func TestMatrixAuthJourneyQuietByDefault(t *testing.T) {
	srv := mxJourneyServer(t)
	stdout, stderr, authErr := mxAuthJourneyCaptured(t, srv)
	if authErr != nil {
		t.Fatalf("authenticate: %v", authErr)
	}
	for name, captured := range map[string]string{"stdout": stdout, "stderr": stderr} {
		for _, lvl := range []string{" DBG ", " TRC "} {
			if strings.Contains(captured, lvl) {
				i := strings.Index(captured, lvl)
				start := i - 40
				if start < 0 {
					start = 0
				}
				end := i + 160
				if end > len(captured) {
					end = len(captured)
				}
				t.Errorf("%s carries debug/trace log noise by default: ...%s...", name, captured[start:end])
			}
		}
	}
}

func TestMatrixAuthJourneyDebugOptIn(t *testing.T) {
	t.Setenv("UNICLIENT_MATRIX_DEBUG", "1")
	srv := mxJourneyServer(t)
	stdout, stderr, authErr := mxAuthJourneyCaptured(t, srv)
	if authErr != nil {
		t.Fatalf("authenticate: %v", authErr)
	}
	if !strings.Contains(stderr, " DBG ") {
		t.Errorf("opt-in debug logging must land on stderr, got: %.300s", stderr)
	}
	if strings.Contains(stdout, " DBG ") {
		i := strings.Index(stdout, " DBG ")
		t.Errorf("opt-in debug logging must never touch stdout (headless -events protocol stream): %.200s", stdout[i:])
	}
}

func mxStr(s string) *string { return &s }

func mxMessageEvt(t *testing.T, contentJSON string) *event.Event {
	t.Helper()
	full := `{"event_id":"$ev:server","room_id":"!room:server","sender":"@alice:server","origin_server_ts":1700000000123,"type":"m.room.message","content":` + contentJSON + `}`
	var evt event.Event
	if err := json.Unmarshal([]byte(full), &evt); err != nil {
		t.Fatalf("build event: %v", err)
	}
	return &evt
}

func TestMatrixEventToMessagePlain(t *testing.T) {
	m := newTestMatrix()
	evt := mxMessageEvt(t, `{"msgtype":"m.text","body":"hello world"}`)

	msg := m.EventToMessage(evt)
	if msg == nil {
		t.Fatal("EventToMessage returned nil for a plain text message")
	}
	if msg.Text != "hello world" {
		t.Errorf("Text = %q, want %q", msg.Text, "hello world")
	}
	if msg.ID != "$ev:server" || msg.ChatID != "!room:server" || msg.SenderID != "@alice:server" {
		t.Errorf("ids wrong: ID=%q ChatID=%q SenderID=%q", msg.ID, msg.ChatID, msg.SenderID)
	}
	if !msg.Timestamp.Equal(time.UnixMilli(1700000000123)) {
		t.Errorf("Timestamp = %v", msg.Timestamp)
	}
	if msg.Status != MessageStatusSent {
		t.Errorf("Status = %v, want Sent", msg.Status)
	}
	if msg.Platform != MxPlatform {
		t.Errorf("Platform = %q", msg.Platform)
	}
	if msg.IsOutgoing {
		t.Error("event from @alice must not be outgoing for @me")
	}
	if msg.Attachments != nil {
		t.Errorf("Attachments = %v, want none", msg.Attachments)
	}
}

func TestMatrixEventToMessageOutgoing(t *testing.T) {
	m := newTestMatrix()
	evt := mxMessageEvt(t, `{"msgtype":"m.text","body":"mine"}`)
	evt.Sender = id.UserID("@me:test")

	if msg := m.EventToMessage(evt); msg == nil || !msg.IsOutgoing {
		t.Fatalf("own message not marked outgoing: %+v", msg)
	}
}

func TestMatrixEventToMessageEditUsesNewContent(t *testing.T) {
	m := newTestMatrix()
	evt := mxMessageEvt(t, `{"msgtype":"m.text","body":"* corrected text","m.new_content":{"msgtype":"m.text","body":"corrected text"}}`)

	msg := m.EventToMessage(evt)
	if msg == nil {
		t.Fatal("nil message for edit event")
	}
	if msg.Text != "corrected text" {
		t.Errorf("edit Text = %q — must come from m.new_content, not the fallback body", msg.Text)
	}
}

func TestMatrixEventToMessageReplyID(t *testing.T) {
	m := newTestMatrix()
	evt := mxMessageEvt(t, `{"msgtype":"m.text","body":"re: hi","m.relates_to":{"m.in_reply_to":{"event_id":"$orig:server"}}}`)

	msg := m.EventToMessage(evt)
	if msg == nil {
		t.Fatal("nil message for reply")
	}
	if msg.ReplyToID != "$orig:server" {
		t.Errorf("ReplyToID = %q, want $orig:server", msg.ReplyToID)
	}
}

func TestMatrixEventToMessageEncryptedFileAttachment(t *testing.T) {
	m := newTestMatrix()
	evt := mxMessageEvt(t, `{"msgtype":"m.file","body":"secret.pdf","file":{"url":"mxc://server/enc1"},"info":{"mimetype":"application/pdf","size":4321,"w":10,"h":20,"duration":3}}`)

	msg := m.EventToMessage(evt)
	if msg == nil || len(msg.Attachments) != 1 {
		t.Fatalf("want 1 attachment, got %+v", msg)
	}
	att := msg.Attachments[0]
	if att.ID != "mxc://server/enc1" {
		t.Errorf("encrypted attachment ID = %q (must be the file URL, not the cleartext one)", att.ID)
	}
	if att.Name != "secret.pdf" || att.MimeType != "application/pdf" || att.Size != 4321 {
		t.Errorf("attachment = %+v", att)
	}
	if att.Width != 10 || att.Height != 20 || att.Duration != 3 {
		t.Errorf("media metadata lost: %+v", att)
	}
	if att.Extra == "" {
		t.Error("encrypted file payload JSON must be preserved in Extra for the download path")
	}
}

func TestMatrixEventToMessagePlainURLAttachment(t *testing.T) {
	m := newTestMatrix()
	evt := mxMessageEvt(t, `{"msgtype":"m.image","body":"pic.png","url":"mxc://server/x1","info":{"mimetype":"image/png","size":99,"w":640,"h":480}}`)

	msg := m.EventToMessage(evt)
	if msg == nil || len(msg.Attachments) != 1 {
		t.Fatalf("want 1 attachment, got %+v", msg)
	}
	att := msg.Attachments[0]
	if att.ID != "mxc://server/x1" || att.Width != 640 || att.Height != 480 || att.Size != 99 {
		t.Errorf("attachment = %+v", att)
	}
}

func TestMatrixEventToMessageNonMessageReturnsNil(t *testing.T) {
	m := newTestMatrix()
	full := `{"event_id":"$st:server","room_id":"!room:server","type":"m.room.name","content":{"name":"New name"}}`
	var evt event.Event
	if err := json.Unmarshal([]byte(full), &evt); err != nil {
		t.Fatal(err)
	}
	if msg := m.EventToMessage(&evt); msg != nil {
		t.Fatalf("state event converted to a message: %+v", msg)
	}
}

func TestMatrixEventToMessageUsesRoomState(t *testing.T) {
	m := newTestMatrix()
	sk := "@alice:server"
	m.ForTestRooms()[id.RoomID("!room:server")] = &MatrixRoomState{
		ID:          id.RoomID("!room:server"),
		IsEncrypted: true,
		Members: map[id.UserID]*MatrixMember{
			id.UserID(sk): {UserID: id.UserID(sk), DisplayName: "Alice", Membership: event.MembershipJoin},
		},
	}
	_ = sk
	evt := mxMessageEvt(t, `{"msgtype":"m.text","body":"secret"}`)

	msg := m.EventToMessage(evt)
	if msg == nil {
		t.Fatal("nil message")
	}
	if msg.SenderName != "Alice" {
		t.Errorf("SenderName = %q, want Alice (from room member state)", msg.SenderName)
	}
	if !msg.IsEncrypted {
		t.Error("IsEncrypted must come from the room state")
	}
}

func TestMatrixRoomToDialogClassification(t *testing.T) {
	m := newTestMatrix()
	base := func() *MatrixRoomState {
		return &MatrixRoomState{ID: id.RoomID("!r:s"), Members: map[id.UserID]*MatrixMember{}}
	}

	space := base()
	space.SpaceParent = id.RoomID("!parent:s")
	if got := m.RoomToDialog(space).Type; got != ChatTypeChannel {
		t.Errorf("space type = %q, want channel", got)
	}

	direct := base()
	direct.IsDirect = true
	if got := m.RoomToDialog(direct).Type; got != ChatTypeDM {
		t.Errorf("direct type = %q, want dm", got)
	}

	two := base()
	two.Members["@a:s"] = &MatrixMember{UserID: "@a:s", Membership: event.MembershipJoin}
	two.Members["@b:s"] = &MatrixMember{UserID: "@b:s", Membership: event.MembershipJoin}
	d := m.RoomToDialog(two)
	if d.Type != ChatTypeDM {
		t.Errorf("2-member type = %q, want dm", d.Type)
	}
	if d.MemberCount != 2 {
		t.Errorf("2-member count = %d", d.MemberCount)
	}

	public := base()
	public.JoinRule = "public"
	public.Members["@a:s"] = &MatrixMember{UserID: "@a:s", Membership: event.MembershipJoin}
	if got := m.RoomToDialog(public).Type; got != ChatTypeChannel {
		t.Errorf("public-join type = %q, want channel", got)
	}

	group := base()
	group.Members["@a:s"] = &MatrixMember{UserID: "@a:s", Membership: event.MembershipJoin}
	group.Members["@b:s"] = &MatrixMember{UserID: "@b:s", Membership: event.MembershipJoin}
	group.Members["@c:s"] = &MatrixMember{UserID: "@c:s", Membership: event.MembershipJoin}
	if got := m.RoomToDialog(group).Type; got != ChatTypeGroup {
		t.Errorf("3-member invite-restricted type = %q, want group", got)
	}
}

func TestMatrixRoomToDialogMemberCountCountsJoinsAndInvitesOnly(t *testing.T) {
	m := newTestMatrix()
	rs := &MatrixRoomState{ID: id.RoomID("!r:s"), Name: "N", Members: map[id.UserID]*MatrixMember{
		"@a:s": {UserID: "@a:s", Membership: event.MembershipJoin},
		"@b:s": {UserID: "@b:s", Membership: event.MembershipInvite},
		"@c:s": {UserID: "@c:s", Membership: event.MembershipLeave},
		"@d:s": {UserID: "@d:s", Membership: event.MembershipKnock},
	}}
	if got := m.RoomToDialog(rs).MemberCount; got != 2 {
		t.Errorf("MemberCount = %d, want 2 (join+invite only; leave/knock excluded)", got)
	}
}

func TestMatrixRoomToDialogTitleFallback(t *testing.T) {
	m := newTestMatrix()
	rs := &MatrixRoomState{ID: id.RoomID("!r:s"), Members: map[id.UserID]*MatrixMember{
		"@me:test": {UserID: "@me:test", DisplayName: "Me", Membership: event.MembershipJoin},
		"@x:s":     {UserID: "@x:s", DisplayName: "Xavier", Membership: event.MembershipJoin},
	}}
	d := m.RoomToDialog(rs)
	if d.Title != "Xavier" {
		t.Errorf("Title = %q — empty room name must fall back to member names (self excluded)", d.Title)
	}
}

func TestMatrixGenerateRoomName(t *testing.T) {
	m := newTestMatrix()
	empty := &MatrixRoomState{ID: id.RoomID("!r:s"), Members: map[id.UserID]*MatrixMember{
		"@me:test": {UserID: "@me:test", DisplayName: "Me", Membership: event.MembershipJoin},
	}}
	if got := m.GenerateRoomName(empty); got != "Empty Room" {
		t.Errorf("self-only room name = %q, want Empty Room", got)
	}

	one := &MatrixRoomState{ID: id.RoomID("!r:s"), Members: map[id.UserID]*MatrixMember{
		"@me:test": {UserID: "@me:test", DisplayName: "Me", Membership: event.MembershipJoin},
		"@x:s":     {UserID: "@x:s", DisplayName: "", Membership: event.MembershipJoin},
	}}
	if got := m.GenerateRoomName(one); got != "@x:s" {
		t.Errorf("empty display name = %q, want the user ID as fallback", got)
	}

	many := &MatrixRoomState{ID: id.RoomID("!r:s"), Members: map[id.UserID]*MatrixMember{
		"@me:test": {UserID: "@me:test", DisplayName: "Me", Membership: event.MembershipJoin},
		"@1:s":     {UserID: "@1:s", DisplayName: "Same", Membership: event.MembershipJoin},
		"@2:s":     {UserID: "@2:s", DisplayName: "Same", Membership: event.MembershipJoin},
		"@3:s":     {UserID: "@3:s", DisplayName: "Same", Membership: event.MembershipJoin},
		"@4:s":     {UserID: "@4:s", DisplayName: "Same", Membership: event.MembershipJoin},
	}}
	if got := m.GenerateRoomName(many); got != "Same, Same and 2 others" {
		t.Errorf("many-room name = %q", got)
	}
}

func TestMatrixIsSpace(t *testing.T) {
	m := newTestMatrix()
	rs := &MatrixRoomState{ID: id.RoomID("!r:s")}
	if m.IsSpace(rs) {
		t.Error("plain room classified as space")
	}
	rs.SpaceParent = id.RoomID("!p:s")
	if !m.IsSpace(rs) {
		t.Error("SpaceParent set but not a space")
	}
	rs.SpaceParent = ""
	rs.Type = ChatType("m.space")
	if !m.IsSpace(rs) {
		t.Error("Type m.space not classified as space")
	}
}

func TestMatrixApplyStateEventFields(t *testing.T) {
	m := newTestMatrix()
	rs := &MatrixRoomState{ID: id.RoomID("!r:s"), Members: map[id.UserID]*MatrixMember{}}

	nameEvt := &event.Event{Type: event.StateRoomName, Content: event.Content{Parsed: &event.RoomNameEventContent{Name: "Renamed"}}}
	m.ApplyStateEvent(rs, nameEvt)
	if rs.Name != "Renamed" {
		t.Errorf("Name = %q", rs.Name)
	}

	topicEvt := &event.Event{Type: event.StateTopic, Content: event.Content{Parsed: &event.TopicEventContent{Topic: "The topic"}}}
	m.ApplyStateEvent(rs, topicEvt)
	if rs.Topic != "The topic" {
		t.Errorf("Topic = %q", rs.Topic)
	}

	avEvt := &event.Event{Type: event.StateRoomAvatar, Content: event.Content{Parsed: &event.RoomAvatarEventContent{URL: id.ContentURIString("mxc://s/av")}}}
	m.ApplyStateEvent(rs, avEvt)
	if rs.AvatarURL != "mxc://s/av" {
		t.Errorf("AvatarURL = %q", rs.AvatarURL)
	}

	encEvt := &event.Event{Type: event.StateEncryption}
	m.ApplyStateEvent(rs, encEvt)
	if !rs.IsEncrypted {
		t.Error("encryption state not applied")
	}

	pl := &event.PowerLevelsEventContent{}
	plEvt := &event.Event{Type: event.StatePowerLevels, Content: event.Content{Parsed: pl}}
	m.ApplyStateEvent(rs, plEvt)
	if rs.PowerLevels != pl {
		t.Error("power levels not applied")
	}

	jrEvt := &event.Event{Type: event.StateJoinRules, Content: event.Content{Parsed: &event.JoinRulesEventContent{JoinRule: "public"}}}
	m.ApplyStateEvent(rs, jrEvt)
	if rs.JoinRule != "public" {
		t.Errorf("JoinRule = %q", rs.JoinRule)
	}

	pinned := []id.EventID{"$p1:s", "$p2:s"}
	piEvt := &event.Event{Type: event.StatePinnedEvents, Content: event.Content{Parsed: &event.PinnedEventsEventContent{Pinned: pinned}}}
	m.ApplyStateEvent(rs, piEvt)
	if len(rs.PinnedIDs) != 2 || rs.PinnedIDs[0] != "$p1:s" {
		t.Errorf("PinnedIDs = %v", rs.PinnedIDs)
	}
}

func TestMatrixApplyStateEventMember(t *testing.T) {
	m := newTestMatrix()
	rs := &MatrixRoomState{ID: id.RoomID("!r:s"), Members: map[id.UserID]*MatrixMember{}}

	evt := &event.Event{
		Type:     event.StateMember,
		StateKey: mxStr("@bob:server"),
		Content:  event.Content{Parsed: &event.MemberEventContent{Membership: event.MembershipJoin, Displayname: "Bob"}},
	}
	m.ApplyStateEvent(rs, evt)

	mem := rs.Members[id.UserID("@bob:server")]
	if mem == nil || mem.Membership != event.MembershipJoin || mem.DisplayName != "Bob" {
		t.Fatalf("member not applied: %+v", mem)
	}
}

func TestMatrixApplyStateEventNilStateKeyDoesNotPanic(t *testing.T) {
	m := newTestMatrix()
	rs := &MatrixRoomState{ID: id.RoomID("!r:s"), Members: map[id.UserID]*MatrixMember{}}

	evt := &event.Event{
		Type:     event.StateMember,
		StateKey: nil,
		Content:  event.Content{Parsed: &event.MemberEventContent{Membership: event.MembershipJoin}},
	}
	defer func() {
		if r := recover(); r != nil {
			t.Fatalf("ApplyStateEvent panicked on a state event without state_key (B-27): %v", r)
		}
	}()
	m.ApplyStateEvent(rs, evt)

	if len(rs.Members) != 0 {
		t.Errorf("member map must stay empty for a stateless member event, got %d entries", len(rs.Members))
	}
}

func TestMatrixHandleMessageEventFiresNewMessage(t *testing.T) {
	m := newTestMatrix()
	var got []Update
	m.OnUpdate(func(u Update) { got = append(got, u) })

	evt := mxMessageEvt(t, `{"msgtype":"m.text","body":"incoming"}`)
	m.HandleMessageEvent(evt)

	if len(got) != 1 {
		t.Fatalf("got %d updates, want 1", len(got))
	}
	u := got[0]
	if u.Type != UpdateNewMessage || u.ChatID != "!room:server" || u.Platform != MxPlatform {
		t.Errorf("update = %+v", u)
	}
	if u.Message == nil || u.Message.Text != "incoming" {
		t.Errorf("message = %+v", u.Message)
	}
}

func TestMatrixHandleMessageEventEditRewritesID(t *testing.T) {
	m := newTestMatrix()
	var got []Update
	m.OnUpdate(func(u Update) { got = append(got, u) })

	evt := mxMessageEvt(t, `{"msgtype":"m.text","body":"* v2","m.new_content":{"msgtype":"m.text","body":"v2"},"m.relates_to":{"rel_type":"m.replace","event_id":"$original:server"}}`)
	m.HandleMessageEvent(evt)

	if len(got) != 1 {
		t.Fatalf("got %d updates, want 1", len(got))
	}
	u := got[0]
	if u.Type != UpdateEditMessage {
		t.Errorf("update type = %v, want UpdateEditMessage", u.Type)
	}
	if u.Message == nil || u.Message.ID != "$original:server" {
		t.Errorf("edit message ID = %+v — must be the original event id", u.Message)
	}
	if u.Message.Text != "v2" {
		t.Errorf("edit text = %q, want v2", u.Message.Text)
	}
}

func TestMatrixGetDialogsRequiresAuth(t *testing.T) {
	m := newTestMatrix()
	_, err := m.GetDialogs(PaginationOpts{Limit: 10})
	if !errors.Is(err, ErrAuth) {
		t.Fatalf("err = %v, want ErrAuth", err)
	}
}

func TestMatrixGetDialogsSortsAndPaginates(t *testing.T) {
	m := mxAuthedCore(t)
	base := time.Date(2026, 9, 24, 12, 0, 0, 0, time.UTC)
	mk := func(room string, offsetMin int, name string) {
		m.ForTestRooms()[id.RoomID(room)] = &MatrixRoomState{
			ID:        id.RoomID(room),
			Name:      name,
			LastEvent: base.Add(time.Duration(offsetMin) * time.Minute),
			Members:   map[id.UserID]*MatrixMember{},
		}
	}
	mk("!old:s", 0, "Old")
	mk("!new:s", 30, "New")
	mk("!mid:s", 10, "Mid")

	all, err := m.GetDialogs(PaginationOpts{Limit: 10})
	if err != nil {
		t.Fatal(err)
	}
	if len(all) != 3 || all[0].Title != "New" || all[1].Title != "Mid" || all[2].Title != "Old" {
		t.Fatalf("order wrong: %v %v %v", all[0].Title, all[1].Title, all[2].Title)
	}

	page, err := m.GetDialogs(PaginationOpts{Limit: 2})
	if err != nil {
		t.Fatal(err)
	}
	if len(page) != 2 || page[0].Title != "New" || page[1].Title != "Mid" {
		t.Fatalf("limit=2 page wrong: %d %v", len(page), page)
	}

	off, err := m.GetDialogs(PaginationOpts{Limit: 2, Offset: "1"})
	if err != nil {
		t.Fatal(err)
	}
	if len(off) != 2 || off[0].Title != "Mid" || off[1].Title != "Old" {
		t.Fatalf("offset=1 page wrong: %d %v", len(off), off)
	}
}

func TestMatrixGetPinnedEvents(t *testing.T) {
	m := newTestMatrix()
	if pins := m.GetPinnedEvents("!r:s"); pins != nil {
		t.Errorf("unknown room pins = %v, want nil", pins)
	}
	m.ForTestRooms()[id.RoomID("!r:s")] = &MatrixRoomState{
		ID:        id.RoomID("!r:s"),
		PinnedIDs: []id.EventID{"$pin:s"},
		Members:   map[id.UserID]*MatrixMember{},
	}
	pins := m.GetPinnedEvents("!r:s")
	if len(pins) != 1 || pins[0] != "$pin:s" {
		t.Errorf("pins = %v", pins)
	}
}
