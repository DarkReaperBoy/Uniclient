package engine

// wallpaper_test.go — slice 218: the wallpaper peer-mirror. The latest
// messageActionSetChatWallPaper service row flips chats.wallpaper_json;
// ChatInfo round-trips it for the GUI renderer.

import (
	"encoding/json"
	"testing"
	"time"

	"uniclient/cores"
)

func wallpaperJSON(t *testing.T, e *Engine) string {
	t.Helper()
	var js string
	if err := e.db.QueryRow(
		`SELECT wallpaper_json FROM chats WHERE account_id = ? AND chat_id = ?`, "a1", "c1").Scan(&js); err != nil {
		t.Fatal(err)
	}
	return js
}

func TestWallpaperMirror(t *testing.T) {
	e := newTestEngine(t)
	seedChannelChat(t, e, "c1", ChatTypeDMVal)

	// Ordinary messages never touch the wallpaper.
	e.cacheMessage("a1", "c1", &cores.Message{ID: "m1", ChatID: "c1", Text: "hi", Timestamp: time.Now()})
	if got := wallpaperJSON(t, e); got != "" {
		t.Fatalf("plain message set wallpaper %q", got)
	}

	// A wallpaper service row mirrors its marshaled WallpaperInfo.
	wp := cores.WallpaperInfo{ID: 42, AccessHash: 4242, DocID: 7, DocHash: 8, Blurred: true}
	e.cacheMessage("a1", "c1", &cores.Message{
		ID: "m2", ChatID: "c1", IsService: true, Text: "changed the chat wallpaper",
		Timestamp: time.Now().Add(time.Second),
		Extra:     map[string]interface{}{"chat_wallpaper": `{"id":42,"access_hash":4242,"doc_id":7,"doc_hash":8,"blurred":true}`},
	})
	got := wallpaperJSON(t, e)
	if got == "" {
		t.Fatal("wallpaper service row did not mirror")
	}
	var back cores.WallpaperInfo
	if err := jsonUnmarshalString(got, &back); err != nil {
		t.Fatalf("mirrored JSON invalid: %v", err)
	}
	if back.ID != wp.ID || back.AccessHash != wp.AccessHash || back.DocID != wp.DocID || !back.Blurred {
		t.Fatalf("mirror drift: %+v", back)
	}

	// A later service row with a different wallpaper replaces it.
	e.cacheMessage("a1", "c1", &cores.Message{
		ID: "m3", ChatID: "c1", IsService: true, Text: "changed the chat wallpaper",
		Timestamp: time.Now().Add(2 * time.Second),
		Extra:     map[string]interface{}{"chat_wallpaper": `{"id":43,"access_hash":4343,"doc_id":9,"doc_hash":10}`},
	})
	if back2 := wallpaperJSON(t, e); back2 == got {
		t.Fatal("second wallpaper did not replace the first")
	}

	// ChatInfo round-trips the wallpaper for the renderer.
	chats, err := e.GetChatList("a1", false, 10, 0)
	if err != nil || len(chats) == 0 {
		t.Fatalf("chat list: %v (%d)", err, len(chats))
	}
	if chats[0].WallpaperJSON == "" {
		t.Fatal("ChatInfo.WallpaperJSON empty after mirror")
	}
	var ci cores.WallpaperInfo
	if err := jsonUnmarshalString(chats[0].WallpaperJSON, &ci); err != nil || ci.ID != 43 {
		t.Fatalf("ChatInfo wallpaper = %q (%v)", chats[0].WallpaperJSON, err)
	}

	// Non-string extra values are skipped, not fatal.
	e.cacheMessage("a1", "c1", &cores.Message{
		ID: "m4", ChatID: "c1", IsService: true, Text: "wallpaper", Timestamp: time.Now().Add(3 * time.Second),
		Extra: map[string]interface{}{"chat_wallpaper": 42},
	})
	if back3 := wallpaperJSON(t, e); back3 == "" {
		t.Fatal("non-string extra clobbered the wallpaper")
	}
}

// jsonUnmarshalString is a tiny helper so the test reads clean.
func jsonUnmarshalString(s string, v interface{}) error {
	return json.Unmarshal([]byte(s), v)
}
