package engine

import "testing"

func TestMediaPreviewLabel(t *testing.T) {
	cases := []struct {
		mt   int
		want string
	}{
		{MediaImage, "Photo"},
		{MediaVideo, "Video"},
		{MediaVoice, "Voice message"},
		{MediaVideoNote, "Video message"},
		{MediaAudio, "Audio file"},
		{MediaGIF, "GIF"},
		{MediaSticker, "Sticker"},
		{MediaFile, "File"},
		{MediaPoll, "Poll"},
		{MediaLocation, "Location"},
		{MediaContact, "Contact"},
		{0, "Media"},
		{99, "Media"},
	}
	for _, c := range cases {
		if got := MediaPreviewLabel(c.mt); got != c.want {
			t.Errorf("MediaPreviewLabel(%d) = %q, want %q", c.mt, got, c.want)
		}
	}
}
