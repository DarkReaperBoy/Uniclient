package cores

// telegram_wallpaper_test.go — slice 218 pins: wire normalization of the
// wallPaper constructor (document coords + settings incl. the pattern
// intensity and the multi-color fills), the settings round-trip used by
// the set/install RPCs, and the service-message Extra extraction that the
// engine mirrors onto chats.wallpaper_json.

import (
	"encoding/json"
	"testing"

	"github.com/gotd/td/tg"
)

func TestWallpaperFromWireImage(t *testing.T) {
	tcore := &TelegramCore{}
	wp := &tg.WallPaper{
		ID:         42,
		AccessHash: 4242,
		Slug:       "custom-abc",
		Creator:    true,
		Document: &tg.Document{
			ID:            1001,
			AccessHash:    2002,
			FileReference: []byte("fileref"),
			MimeType:      "image/jpeg",
		},
	}
	wp.Settings = tg.WallPaperSettings{Blur: true, Motion: true}
	wp.Settings.SetIntensity(50)
	wp.SetSettings(wp.Settings)

	info := tcore.wallpaperFromWire(wp)
	if info.ID != 42 || info.AccessHash != 4242 {
		t.Fatalf("wallpaper ref = %d/%d, want 42/4242", info.ID, info.AccessHash)
	}
	if info.DocID != 1001 || info.DocHash != 2002 || info.DocRef != "fileref" {
		t.Fatalf("doc coords = %d/%d/%q", info.DocID, info.DocHash, info.DocRef)
	}
	if !info.IsPhoto {
		t.Fatal("image wallpaper not marked IsPhoto")
	}
	if !info.Creator {
		t.Fatal("creator flag lost")
	}
	if !info.Blurred || !info.Motion {
		t.Fatalf("settings = blur:%v motion:%v, want both true", info.Blurred, info.Motion)
	}
	if info.Intensity != 50 {
		t.Fatalf("intensity = %d, want 50", info.Intensity)
	}
}

func TestWallpaperFromWireFillColors(t *testing.T) {
	tcore := &TelegramCore{}
	wp := &tg.WallPaper{ID: 7}
	wp.Settings = tg.WallPaperSettings{Rotation: 90}
	wp.Settings.SetBackgroundColor(0x112233)
	wp.Settings.SetSecondBackgroundColor(0x445566)
	wp.Settings.SetThirdBackgroundColor(0x778899)
	wp.Settings.SetFourthBackgroundColor(0xAABBCC)
	wp.SetSettings(wp.Settings)

	info := tcore.wallpaperFromWire(wp)
	want := []int{0x112233, 0x445566, 0x778899, 0xAABBCC}
	if len(info.Colors) != len(want) {
		t.Fatalf("colors = %v, want %v", info.Colors, want)
	}
	for i, c := range want {
		if info.Colors[i] != c {
			t.Fatalf("color[%d] = %06X, want %06X", i, info.Colors[i], c)
		}
	}
	if info.Rotation != 90 {
		t.Fatalf("rotation = %d, want 90", info.Rotation)
	}
}

func TestWallpaperFromWireNoFile(t *testing.T) {
	tcore := &TelegramCore{}
	// wallPaperNoFile and non-WallPaper classes normalize to the zero
	// info (the caller treats that as "no wallpaper").
	if info := tcore.wallpaperFromWire(&tg.WallPaperNoFile{ID: 9}); info.ID != 0 {
		t.Fatalf("no-file wallpaper produced %+v", info)
	}
	if info := tcore.wallpaperFromWire(nil); info.ID != 0 || info.DocID != 0 {
		t.Fatalf("nil wallpaper produced %+v", info)
	}
}

func TestWallpaperSettingsRoundTrip(t *testing.T) {
	info := WallpaperInfo{
		Blurred:   true,
		Motion:    false,
		Rotation:  45,
		Intensity: -40,
		Colors:    []int{0x010203, 0x040506, 0x070809, 0x0A0B0C},
	}
	s := wallpaperSettingsFromInfo(info)
	if !s.Blur || s.Rotation != 45 {
		t.Fatalf("settings = %+v", s)
	}
	if !s.Flags.Has(3) || s.Intensity != -40 {
		t.Fatalf("intensity = %d has3=%v, want -40 true", s.Intensity, s.Flags.Has(3))
	}
	for i, want := range info.Colors {
		var got int
		switch i {
		case 0:
			got = s.BackgroundColor
		case 1:
			got = s.SecondBackgroundColor
		case 2:
			got = s.ThirdBackgroundColor
		case 3:
			got = s.FourthBackgroundColor
		}
		if got != want {
			t.Fatalf("color[%d] = %06X, want %06X", i, got, want)
		}
	}
	// Round-trip back through the wire normalizer with flags armed the
	// way the API returns them.
	wp := &tg.WallPaper{ID: 5, Settings: s}
	wp.SetSettings(s)
	info2 := (&TelegramCore{}).wallpaperFromWire(wp)
	if info2.Blurred != info.Blurred || info2.Rotation != info.Rotation ||
		info2.Intensity != info.Intensity || len(info2.Colors) != 4 {
		t.Fatalf("round-trip drift: %+v", info2)
	}
}

func TestWallpaperExtraJSONRoundTrip(t *testing.T) {
	// The engine stores Extra["chat_wallpaper"] as marshaled
	// WallpaperInfo — pinned here so the GUI-side parse never drifts.
	info := WallpaperInfo{
		ID: 42, AccessHash: 4242, DocID: 1001, DocHash: 2002,
		Blurred: true, Pattern: false, Colors: []int{0x336699},
	}
	raw, err := json.Marshal(info)
	if err != nil {
		t.Fatal(err)
	}
	var back WallpaperInfo
	if err := json.Unmarshal(raw, &back); err != nil {
		t.Fatal(err)
	}
	if back.ID != 42 || back.AccessHash != 4242 || back.DocID != 1001 ||
		back.DocHash != 2002 || !back.Blurred || len(back.Colors) != 1 {
		t.Fatalf("JSON round-trip drift: %+v", back)
	}
}

func TestWallpaperSettingsFromInfoEmpty(t *testing.T) {
	// Zero info must produce a valid settings struct with no color flags
	// armed (the RPC accepts it — blur/motion off).
	s := wallpaperSettingsFromInfo(WallpaperInfo{})
	if s.Flags.Has(0) || s.Flags.Has(4) || s.Flags.Has(5) || s.Flags.Has(6) || s.Flags.Has(3) {
		t.Fatalf("empty info armed color flags: %+v", s.Flags)
	}
	if s.Blur || s.Motion {
		t.Fatalf("empty info armed blur/motion: %+v", s)
	}
}
