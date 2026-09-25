package cores

import (
	"encoding/json"
	"testing"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

// Hostile-homeserver fuzzing (slice 261): a malicious or buggy Matrix
// server controls every sync event body — the conversion and handler
// layer must never panic (§1.10). JSON goes through the REAL
// event.Event unmarshal (v0.30 Content.Raw is a map — the same shape
// sync delivers), then through the production call paths.

func mxFuzzUnmarshal(t *testing.T, data []byte) *event.Event {
	t.Helper()
	var evt event.Event
	if err := json.Unmarshal(data, &evt); err != nil {
		t.Skip() // malformed JSON is mautrix's (tested) layer; we test OUR handlers
	}
	return &evt
}

// FuzzMatrixEventToMessage: the conversion every message text/photo/
// file passes through (GetMessages pagination, sync, edits, replies).
func FuzzMatrixEventToMessage(f *testing.F) {
	addMxMessageSeeds(f)
	core := NewMatrixCore(nil)
	f.Fuzz(func(t *testing.T, data []byte) {
		evt := mxFuzzUnmarshal(t, data)
		_ = core.eventToMessage(evt) // nil for non-messages is correct; a panic is not
	})
}

// FuzzMatrixStateEvent: applyStateEvent — the state machine that
// feeds room names/topics/members/encryption/pins (includes the
// B-27 no-state_key regression seed).
func FuzzMatrixStateEvent(f *testing.F) {
	f.Add([]byte(`{"type":"m.room.member","state_key":"@a:b","room_id":"!r:s","sender":"@a:b","content":{"membership":"join","displayname":"A"}}`))
	f.Add([]byte(`{"type":"m.room.member","room_id":"!r:s","content":{"membership":"leave"}}`)) // B-27: no state_key
	f.Add([]byte(`{"type":"m.room.name","state_key":"","room_id":"!r:s","content":{"name":"N"}}`))
	f.Add([]byte(`{"type":"m.room.topic","state_key":"","room_id":"!r:s","content":{"topic":"T"}}`))
	f.Add([]byte(`{"type":"m.room.avatar","state_key":"","room_id":"!r:s","content":{"url":"mxc://s/a"}}`))
	f.Add([]byte(`{"type":"m.room.encryption","state_key":"","room_id":"!r:s","content":{"algorithm":"m.megolm.v1.aes-sha2"}}`))
	f.Add([]byte(`{"type":"m.room.join_rules","state_key":"","room_id":"!r:s","content":{"join_rule":"public"}}`))
	f.Add([]byte(`{"type":"m.room.pinned_events","state_key":"","room_id":"!r:s","content":{"pinned":["$1:s","$2:s"]}}`))
	f.Add([]byte(`{"type":"m.room.power_levels","state_key":"","room_id":"!r:s","content":{"users":{"@a:b":100}}}`))
	f.Add([]byte(`{"type":"unknown.thing","state_key":"k","content":{}}`))
	core := NewMatrixCore(nil)
	f.Fuzz(func(t *testing.T, data []byte) {
		evt := mxFuzzUnmarshal(t, data)
		rs := &matrixRoomState{
			ID:      evt.RoomID,
			Members: map[id.UserID]*matrixMember{},
		}
		core.applyStateEvent(rs, evt)
	})
}

// FuzzMatrixHandleMessageEvent: the sync-path dispatcher (new message
// vs edit rewrite vs non-message no-op, update fan-out).
func FuzzMatrixHandleMessageEvent(f *testing.F) {
	addMxMessageSeeds(f)
	core := NewMatrixCore(nil)
	f.Fuzz(func(t *testing.T, data []byte) {
		evt := mxFuzzUnmarshal(t, data)
		core.handleMessageEvent(evt)
	})
}

func addMxMessageSeeds(f *testing.F) {
	f.Add([]byte(`{"type":"m.room.message","event_id":"$e:s","room_id":"!r:s","sender":"@a:b","origin_server_ts":1700000000123,"content":{"msgtype":"m.text","body":"hello"}}`))
	f.Add([]byte(`{"type":"m.room.message","event_id":"$e:s","room_id":"!r:s","sender":"@me:b","origin_server_ts":1700000000123,"content":{"msgtype":"m.text","body":"mine"}}`))
	f.Add([]byte(`{"type":"m.room.message","event_id":"$e:s","room_id":"!r:s","sender":"@a:b","origin_server_ts":1,"content":{"msgtype":"m.text","body":"* v2","m.new_content":{"msgtype":"m.text","body":"v2"},"m.relates_to":{"rel_type":"m.replace","event_id":"$orig:s"}}}`))
	f.Add([]byte(`{"type":"m.room.message","event_id":"$e:s","room_id":"!r:s","sender":"@a:b","origin_server_ts":1,"content":{"msgtype":"m.text","body":"re","m.relates_to":{"m.in_reply_to":{"event_id":"$o:s"}}}}`))
	f.Add([]byte(`{"type":"m.room.message","event_id":"$e:s","room_id":"!r:s","sender":"@a:b","origin_server_ts":1,"content":{"msgtype":"m.image","body":"p.png","url":"mxc://s/x","info":{"mimetype":"image/png","size":9,"w":1,"h":2}}}`))
	f.Add([]byte(`{"type":"m.room.message","event_id":"$e:s","room_id":"!r:s","sender":"@a:b","origin_server_ts":1,"content":{"msgtype":"m.file","body":"s.pdf","file":{"url":"mxc://s/e"}}}`))
	f.Add([]byte(`{"type":"m.room.topic","event_id":"$e:s","room_id":"!r:s","sender":"@a:b","content":{"topic":"not a message"}}`))
	f.Add([]byte(`{}`))
}
