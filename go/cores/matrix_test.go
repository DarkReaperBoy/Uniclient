package cores

import (
	"encoding/json"
	"errors"
	"testing"
	"time"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

// Matrix core state-level tests: the core had ZERO test files before
// slice 248. Everything here runs against pure state seams —
// eventToMessage / roomToDialog / generateRoomName / isSpace /
// applyStateEvent / handleMessageEvent / GetDialogs / getPinnedEvents —
// with scripted mautrix events, no network.

func newTestMatrix() *MatrixCore {
	m := NewMatrixCore(nil)
	m.userID = id.UserID("@me:test")
	return m
}

func mxStr(s string) *string { return &s }

// mxMessageEvt builds a real m.room.message event by unmarshalling full
// event JSON — exactly how sync events arrive (Content.Raw as a map,
// ParseRaw runs inside the production call paths).
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

	msg := m.eventToMessage(evt)
	if msg == nil {
		t.Fatal("eventToMessage returned nil for a plain text message")
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
	if msg.Platform != mxPlatform {
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

	if msg := m.eventToMessage(evt); msg == nil || !msg.IsOutgoing {
		t.Fatalf("own message not marked outgoing: %+v", msg)
	}
}

func TestMatrixEventToMessageEditUsesNewContent(t *testing.T) {
	m := newTestMatrix()
	evt := mxMessageEvt(t, `{"msgtype":"m.text","body":"* corrected text","m.new_content":{"msgtype":"m.text","body":"corrected text"}}`)

	msg := m.eventToMessage(evt)
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

	msg := m.eventToMessage(evt)
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

	msg := m.eventToMessage(evt)
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

	msg := m.eventToMessage(evt)
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
	if msg := m.eventToMessage(&evt); msg != nil {
		t.Fatalf("state event converted to a message: %+v", msg)
	}
}

func TestMatrixEventToMessageUsesRoomState(t *testing.T) {
	m := newTestMatrix()
	sk := "@alice:server"
	m.rooms[id.RoomID("!room:server")] = &matrixRoomState{
		ID:          id.RoomID("!room:server"),
		IsEncrypted: true,
		Members: map[id.UserID]*matrixMember{
			id.UserID(sk): {UserID: id.UserID(sk), DisplayName: "Alice", Membership: event.MembershipJoin},
		},
	}
	_ = sk
	evt := mxMessageEvt(t, `{"msgtype":"m.text","body":"secret"}`)

	msg := m.eventToMessage(evt)
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
	base := func() *matrixRoomState {
		return &matrixRoomState{ID: id.RoomID("!r:s"), Members: map[id.UserID]*matrixMember{}}
	}

	space := base()
	space.SpaceParent = id.RoomID("!parent:s")
	if got := m.roomToDialog(space).Type; got != ChatTypeChannel {
		t.Errorf("space type = %q, want channel", got)
	}

	direct := base()
	direct.IsDirect = true
	if got := m.roomToDialog(direct).Type; got != ChatTypeDM {
		t.Errorf("direct type = %q, want dm", got)
	}

	two := base()
	two.Members["@a:s"] = &matrixMember{UserID: "@a:s", Membership: event.MembershipJoin}
	two.Members["@b:s"] = &matrixMember{UserID: "@b:s", Membership: event.MembershipJoin}
	d := m.roomToDialog(two)
	if d.Type != ChatTypeDM {
		t.Errorf("2-member type = %q, want dm", d.Type)
	}
	if d.MemberCount != 2 {
		t.Errorf("2-member count = %d", d.MemberCount)
	}

	public := base()
	public.JoinRule = "public"
	public.Members["@a:s"] = &matrixMember{UserID: "@a:s", Membership: event.MembershipJoin}
	if got := m.roomToDialog(public).Type; got != ChatTypeChannel {
		t.Errorf("public-join type = %q, want channel", got)
	}

	group := base()
	group.Members["@a:s"] = &matrixMember{UserID: "@a:s", Membership: event.MembershipJoin}
	group.Members["@b:s"] = &matrixMember{UserID: "@b:s", Membership: event.MembershipJoin}
	group.Members["@c:s"] = &matrixMember{UserID: "@c:s", Membership: event.MembershipJoin}
	if got := m.roomToDialog(group).Type; got != ChatTypeGroup {
		t.Errorf("3-member invite-restricted type = %q, want group", got)
	}
}

func TestMatrixRoomToDialogMemberCountCountsJoinsAndInvitesOnly(t *testing.T) {
	m := newTestMatrix()
	rs := &matrixRoomState{ID: id.RoomID("!r:s"), Name: "N", Members: map[id.UserID]*matrixMember{
		"@a:s": {UserID: "@a:s", Membership: event.MembershipJoin},
		"@b:s": {UserID: "@b:s", Membership: event.MembershipInvite},
		"@c:s": {UserID: "@c:s", Membership: event.MembershipLeave},
		"@d:s": {UserID: "@d:s", Membership: event.MembershipKnock},
	}}
	if got := m.roomToDialog(rs).MemberCount; got != 2 {
		t.Errorf("MemberCount = %d, want 2 (join+invite only; leave/knock excluded)", got)
	}
}

func TestMatrixRoomToDialogTitleFallback(t *testing.T) {
	m := newTestMatrix()
	rs := &matrixRoomState{ID: id.RoomID("!r:s"), Members: map[id.UserID]*matrixMember{
		"@me:test": {UserID: "@me:test", DisplayName: "Me", Membership: event.MembershipJoin},
		"@x:s":     {UserID: "@x:s", DisplayName: "Xavier", Membership: event.MembershipJoin},
	}}
	d := m.roomToDialog(rs)
	if d.Title != "Xavier" {
		t.Errorf("Title = %q — empty room name must fall back to member names (self excluded)", d.Title)
	}
}

func TestMatrixGenerateRoomName(t *testing.T) {
	m := newTestMatrix()
	empty := &matrixRoomState{ID: id.RoomID("!r:s"), Members: map[id.UserID]*matrixMember{
		"@me:test": {UserID: "@me:test", DisplayName: "Me", Membership: event.MembershipJoin},
	}}
	if got := m.generateRoomName(empty); got != "Empty Room" {
		t.Errorf("self-only room name = %q, want Empty Room", got)
	}

	one := &matrixRoomState{ID: id.RoomID("!r:s"), Members: map[id.UserID]*matrixMember{
		"@me:test": {UserID: "@me:test", DisplayName: "Me", Membership: event.MembershipJoin},
		"@x:s":     {UserID: "@x:s", DisplayName: "", Membership: event.MembershipJoin},
	}}
	if got := m.generateRoomName(one); got != "@x:s" {
		t.Errorf("empty display name = %q, want the user ID as fallback", got)
	}

	// Four OTHERS with identical display names: deterministic despite
	// map iteration order, pinning the "A, B and N others" shape.
	many := &matrixRoomState{ID: id.RoomID("!r:s"), Members: map[id.UserID]*matrixMember{
		"@me:test": {UserID: "@me:test", DisplayName: "Me", Membership: event.MembershipJoin},
		"@1:s":     {UserID: "@1:s", DisplayName: "Same", Membership: event.MembershipJoin},
		"@2:s":     {UserID: "@2:s", DisplayName: "Same", Membership: event.MembershipJoin},
		"@3:s":     {UserID: "@3:s", DisplayName: "Same", Membership: event.MembershipJoin},
		"@4:s":     {UserID: "@4:s", DisplayName: "Same", Membership: event.MembershipJoin},
	}}
	if got := m.generateRoomName(many); got != "Same, Same and 2 others" {
		t.Errorf("many-room name = %q", got)
	}
}

func TestMatrixIsSpace(t *testing.T) {
	m := newTestMatrix()
	rs := &matrixRoomState{ID: id.RoomID("!r:s")}
	if m.isSpace(rs) {
		t.Error("plain room classified as space")
	}
	rs.SpaceParent = id.RoomID("!p:s")
	if !m.isSpace(rs) {
		t.Error("SpaceParent set but not a space")
	}
	rs.SpaceParent = ""
	rs.Type = ChatType("m.space")
	if !m.isSpace(rs) {
		t.Error("Type m.space not classified as space")
	}
}

func TestMatrixApplyStateEventFields(t *testing.T) {
	m := newTestMatrix()
	rs := &matrixRoomState{ID: id.RoomID("!r:s"), Members: map[id.UserID]*matrixMember{}}

	nameEvt := &event.Event{Type: event.StateRoomName, Content: event.Content{Parsed: &event.RoomNameEventContent{Name: "Renamed"}}}
	m.applyStateEvent(rs, nameEvt)
	if rs.Name != "Renamed" {
		t.Errorf("Name = %q", rs.Name)
	}

	topicEvt := &event.Event{Type: event.StateTopic, Content: event.Content{Parsed: &event.TopicEventContent{Topic: "The topic"}}}
	m.applyStateEvent(rs, topicEvt)
	if rs.Topic != "The topic" {
		t.Errorf("Topic = %q", rs.Topic)
	}

	avEvt := &event.Event{Type: event.StateRoomAvatar, Content: event.Content{Parsed: &event.RoomAvatarEventContent{URL: id.ContentURIString("mxc://s/av")}}}
	m.applyStateEvent(rs, avEvt)
	if rs.AvatarURL != "mxc://s/av" {
		t.Errorf("AvatarURL = %q", rs.AvatarURL)
	}

	encEvt := &event.Event{Type: event.StateEncryption}
	m.applyStateEvent(rs, encEvt)
	if !rs.IsEncrypted {
		t.Error("encryption state not applied")
	}

	pl := &event.PowerLevelsEventContent{}
	plEvt := &event.Event{Type: event.StatePowerLevels, Content: event.Content{Parsed: pl}}
	m.applyStateEvent(rs, plEvt)
	if rs.PowerLevels != pl {
		t.Error("power levels not applied")
	}

	jrEvt := &event.Event{Type: event.StateJoinRules, Content: event.Content{Parsed: &event.JoinRulesEventContent{JoinRule: "public"}}}
	m.applyStateEvent(rs, jrEvt)
	if rs.JoinRule != "public" {
		t.Errorf("JoinRule = %q", rs.JoinRule)
	}

	pinned := []id.EventID{"$p1:s", "$p2:s"}
	piEvt := &event.Event{Type: event.StatePinnedEvents, Content: event.Content{Parsed: &event.PinnedEventsEventContent{Pinned: pinned}}}
	m.applyStateEvent(rs, piEvt)
	if len(rs.PinnedIDs) != 2 || rs.PinnedIDs[0] != "$p1:s" {
		t.Errorf("PinnedIDs = %v", rs.PinnedIDs)
	}
}

func TestMatrixApplyStateEventMember(t *testing.T) {
	m := newTestMatrix()
	rs := &matrixRoomState{ID: id.RoomID("!r:s"), Members: map[id.UserID]*matrixMember{}}

	evt := &event.Event{
		Type:     event.StateMember,
		StateKey: mxStr("@bob:server"),
		Content:  event.Content{Parsed: &event.MemberEventContent{Membership: event.MembershipJoin, Displayname: "Bob"}},
	}
	m.applyStateEvent(rs, evt)

	mem := rs.Members[id.UserID("@bob:server")]
	if mem == nil || mem.Membership != event.MembershipJoin || mem.DisplayName != "Bob" {
		t.Fatalf("member not applied: %+v", mem)
	}
}

// TestMatrixApplyStateEventNilStateKeyDoesNotPanic: BUGS B-27 — the
// StateMember branch dereferenced *evt.StateKey with no nil guard while
// BOTH sibling handlers (handleMemberEvent and the sync room loop) check
// it first. A state event without state_key (malicious/buggy homeserver)
// crashed the core. RED before the fix.
func TestMatrixApplyStateEventNilStateKeyDoesNotPanic(t *testing.T) {
	m := newTestMatrix()
	rs := &matrixRoomState{ID: id.RoomID("!r:s"), Members: map[id.UserID]*matrixMember{}}

	evt := &event.Event{
		Type:     event.StateMember,
		StateKey: nil, // malformed state event
		Content:  event.Content{Parsed: &event.MemberEventContent{Membership: event.MembershipJoin}},
	}
	defer func() {
		if r := recover(); r != nil {
			t.Fatalf("applyStateEvent panicked on a state event without state_key (B-27): %v", r)
		}
	}()
	m.applyStateEvent(rs, evt)

	if len(rs.Members) != 0 {
		t.Errorf("member map must stay empty for a stateless member event, got %d entries", len(rs.Members))
	}
}

func TestMatrixHandleMessageEventFiresNewMessage(t *testing.T) {
	m := newTestMatrix()
	var got []Update
	m.OnUpdate(func(u Update) { got = append(got, u) })

	evt := mxMessageEvt(t, `{"msgtype":"m.text","body":"incoming"}`)
	m.handleMessageEvent(evt)

	if len(got) != 1 {
		t.Fatalf("got %d updates, want 1", len(got))
	}
	u := got[0]
	if u.Type != UpdateNewMessage || u.ChatID != "!room:server" || u.Platform != mxPlatform {
		t.Errorf("update = %+v", u)
	}
	if u.Message == nil || u.Message.Text != "incoming" {
		t.Errorf("message = %+v", u.Message)
	}
}

// TestMatrixHandleMessageEventEditRewritesID: an edit must fire
// UpdateEditMessage whose Message.ID is the ORIGINAL event id (the id
// consumers use to replace the row), not the edit event's own id.
func TestMatrixHandleMessageEventEditRewritesID(t *testing.T) {
	m := newTestMatrix()
	var got []Update
	m.OnUpdate(func(u Update) { got = append(got, u) })

	evt := mxMessageEvt(t, `{"msgtype":"m.text","body":"* v2","m.new_content":{"msgtype":"m.text","body":"v2"},"m.relates_to":{"rel_type":"m.replace","event_id":"$original:server"}}`)
	m.handleMessageEvent(evt)

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
	m := newTestMatrix()
	m.authed = true
	base := time.Date(2026, 9, 24, 12, 0, 0, 0, time.UTC)
	mk := func(room string, offsetMin int, name string) {
		m.rooms[id.RoomID(room)] = &matrixRoomState{
			ID:        id.RoomID(room),
			Name:      name,
			LastEvent: base.Add(time.Duration(offsetMin) * time.Minute),
			Members:   map[id.UserID]*matrixMember{},
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
	if pins := m.getPinnedEvents("!r:s"); pins != nil {
		t.Errorf("unknown room pins = %v, want nil", pins)
	}
	m.rooms[id.RoomID("!r:s")] = &matrixRoomState{
		ID:        id.RoomID("!r:s"),
		PinnedIDs: []id.EventID{"$pin:s"},
		Members:   map[id.UserID]*matrixMember{},
	}
	pins := m.getPinnedEvents("!r:s")
	if len(pins) != 1 || pins[0] != "$pin:s" {
		t.Errorf("pins = %v", pins)
	}
}
