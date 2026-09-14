package cores

// telegram_savedmusic_test.go — slice 206 tests-first: profile-music
// ("saved music", tdesktop Aug 2026) pure builders — document → track
// normalization (voice notes excluded, honest filename fallback) and the
// account.saveMusic request shape (unsave / after_id flag mapping).

import (
	"testing"

	"github.com/gotd/td/tg"
)

func musicDocFixture(voice bool, title, performer string, dur int) *tg.Document {
	audio := &tg.DocumentAttributeAudio{
		Duration: dur,
	}
	if title != "" {
		audio.SetTitle(title)
	}
	if performer != "" {
		audio.SetPerformer(performer)
	}
	if voice {
		audio.SetVoice(true)
	}
	return &tg.Document{
		ID:            7001,
		AccessHash:    -1234567890,
		FileReference: []byte{1, 2, 3, 9},
		MimeType:      "audio/mpeg",
		Size:          194_577,
		Attributes: []tg.DocumentAttributeClass{
			audio,
			&tg.DocumentAttributeFilename{FileName: "song.mp3"},
		},
	}
}

func TestNormalizeMusicDoc(t *testing.T) {
	tr, ok := normalizeMusicDoc(musicDocFixture(false, "Nightcall", "Kavinsky", 257))
	if !ok {
		t.Fatal("song document was rejected")
	}
	if tr.DocID != "7001" || tr.AccessHash != -1234567890 {
		t.Errorf("doc id/hash = %q/%d", tr.DocID, tr.AccessHash)
	}
	if tr.Title != "Nightcall" || tr.Performer != "Kavinsky" {
		t.Errorf("tags = %q/%q", tr.Title, tr.Performer)
	}
	if tr.Duration != 257 || tr.Size != 194_577 || tr.MimeType != "audio/mpeg" {
		t.Errorf("duration/size/mime = %d/%d/%q", tr.Duration, tr.Size, tr.MimeType)
	}
	if tr.FileRefB64 == "" {
		t.Error("file reference not carried for downloads")
	}
}

func TestNormalizeMusicDocVoiceRejected(t *testing.T) {
	if _, ok := normalizeMusicDoc(musicDocFixture(true, "", "", 12)); ok {
		t.Error("voice note must not be profile music (isSong gate)")
	}
}

func TestNormalizeMusicDocFilenameFallback(t *testing.T) {
	tr, ok := normalizeMusicDoc(musicDocFixture(false, "", "", 200))
	if !ok {
		t.Fatal("untitled song rejected (isSong has no title requirement)")
	}
	if tr.Title != "" || tr.FileName != "song.mp3" {
		t.Errorf("untitled song must keep empty title + file name: %+v", tr)
	}
}

func TestNormalizeMusicDocNonAudio(t *testing.T) {
	if _, ok := normalizeMusicDoc(&tg.Document{ID: 8, Attributes: []tg.DocumentAttributeClass{
		&tg.DocumentAttributeImageSize{W: 100, H: 100},
	}}); ok {
		t.Error("non-audio document must not be profile music")
	}
}

func TestProfileMusicSaveRequest(t *testing.T) {
	// plain save: no flags.
	req := profileMusicSaveRequest(MusicTrackInfo{DocID: "7001", AccessHash: 5, FileRefB64: ""}, MusicTrackInfo{}, false)
	if req.Unsave {
		t.Error("plain save must not set unsave")
	}
	if _, ok := req.GetAfterID(); ok {
		t.Error("plain save must not carry after_id")
	}
	id, ok := req.ID.(*tg.InputDocument)
	if !ok || id.ID != 7001 || id.AccessHash != 5 {
		t.Fatalf("id = %+v (%T)", req.ID, req.ID)
	}
	if after, ok := req.GetAfterID(); ok {
		_ = after
		t.Error("plain save must not carry an after document")
	}
}

func TestProfileMusicSaveRequestAfter(t *testing.T) {
	// reorder: after_id set with the after document.
	req := profileMusicSaveRequest(
		MusicTrackInfo{DocID: "7001", AccessHash: 5},
		MusicTrackInfo{DocID: "7002", AccessHash: 6}, false)
	if req.Unsave {
		t.Error("reorder must not set unsave")
	}
	if _, ok := req.GetAfterID(); !ok {
		t.Error("reorder must set the after_id flag")
	}
	after, ok := req.AfterID.(*tg.InputDocument)
	if !ok || after.ID != 7002 || after.AccessHash != 6 {
		t.Fatalf("after = %+v (%T)", req.AfterID, req.AfterID)
	}
}

func TestProfileMusicSaveRequestUnsave(t *testing.T) {
	req := profileMusicSaveRequest(MusicTrackInfo{DocID: "7001", AccessHash: 5}, MusicTrackInfo{}, true)
	if !req.Unsave {
		t.Error("removal must set unsave")
	}
	if _, ok := req.GetAfterID(); ok {
		t.Error("removal must not carry after_id")
	}
}

func TestAudioSendMediaRequest(t *testing.T) {
	track := MusicTrackInfo{
		DocID: "7001", AccessHash: -42, FileRefB64: "AQID",
		Title: "Nightcall", Performer: "Kavinsky",
	}
	req := audioSendMediaRequest(track, "a caption", true, 3600, 99)
	md, ok := req.Media.(*tg.InputMediaDocument)
	if !ok {
		t.Fatalf("media type %T, want InputMediaDocument", req.Media)
	}
	doc, ok := md.ID.(*tg.InputDocument)
	if !ok {
		t.Fatalf("document type %T", md.ID)
	}
	if doc.ID != 7001 || doc.AccessHash != -42 {
		t.Errorf("doc id/hash = %d/%d, want 7001/-42", doc.ID, doc.AccessHash)
	}
	if string(doc.FileReference) != "\x01\x02\x03" {
		t.Errorf("file reference = %v, want decoded bytes", doc.FileReference)
	}
	if req.Message != "a caption" {
		t.Errorf("caption = %q", req.Message)
	}
	if !req.Silent {
		t.Error("silent flag lost")
	}
	if !req.ScheduleDate || req.ScheduleDate != 3600 {
		t.Errorf("schedule date = %d, want 3600", req.ScheduleDate)
	}

	// No caption / no schedule / no ref: honest minimal request.
	req2 := audioSendMediaRequest(MusicTrackInfo{DocID: "8"}, "", false, 0, 7)
	if req2.Message != "" || req2.Silent || req2.ScheduleDate {
		t.Errorf("minimal request carries flags: %+v", req2)
	}
	d2 := req2.Media.(*tg.InputMediaDocument).ID.(*tg.InputDocument)
	if d2.ID != 8 || d2.AccessHash != 0 || d2.FileReference != nil {
		t.Errorf("minimal doc ref wrong: %+v", d2)
	}
}
