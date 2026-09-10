package gui

// Export data wizard (slice 100, matrix row 208): pure helpers — option
// group tables, size-limit parsing, progress percent, error text, and
// dialog-surface wiring.

import (
	"testing"

	"uniclient/engine"
)

func TestExportOptionGroupsCoverSettings(t *testing.T) {
	// Every option key maps to a real ExportSettings field name; the
	// wizard is honest — no option without engine behavior.
	groups := exportOptionGroups()
	seen := map[string]bool{}
	for _, g := range groups {
		for _, o := range g.opts {
			if seen[o.key] {
				t.Errorf("duplicate option key %q", o.key)
			}
			seen[o.key] = true
			if o.label == "" {
				t.Errorf("option %q has empty label", o.key)
			}
		}
	}
	want := []string{
		"personal_info", "contacts", "stories", "profile_music",
		"personal_chats", "bot_chats", "private_groups", "private_channels",
		"public_groups", "public_channels",
		"media_photos", "media_video", "media_voice", "media_video_message",
		"media_sticker", "media_gif", "media_file",
		"sessions", "other_data",
	}
	for _, k := range want {
		if !seen[k] {
			t.Errorf("option group missing key %q", k)
		}
	}
}

func TestParseExportSizeLimit(t *testing.T) {
	cases := []struct {
		in   string
		want int
	}{
		{"", 0},
		{"1536", 1536},
		{"  200 ", 200},
		{"abc", 0},
		{"-5", 0},
		{"99999999", 8192}, // clamped to the engine's 8 GB ceiling
	}
	for _, tc := range cases {
		if got := parseExportSizeLimit(tc.in); got != tc.want {
			t.Errorf("parseExportSizeLimit(%q) = %d, want %d", tc.in, got, tc.want)
		}
	}
}

func TestExportProgressPercent(t *testing.T) {
	cases := []struct {
		step, total int
		prog        float64
		want        float32
	}{
		{0, 4, 0.5, 0.125},
		{3, 4, 1.0, 1.0},
		{0, 0, 0.5, 0}, // no steps: never divide by zero
		{1, 4, 0, 0.25},
	}
	for _, tc := range cases {
		if got := exportProgressPercent(tc.step, tc.total, tc.prog); got != tc.want {
			t.Errorf("exportProgressPercent(%d,%d,%v) = %v, want %v", tc.step, tc.total, tc.prog, got, tc.want)
		}
	}
}

func TestExportErrorText(t *testing.T) {
	cases := []struct {
		ev   engine.ExportErrorEvent
		want string
	}{
		{
			engine.ExportErrorEvent{ErrorType: "takeout_delay", HoursRemaining: 7, Description: "Slow mode"},
			"Telegram limits data exports — try again in 7 h.",
		},
		{
			engine.ExportErrorEvent{ErrorType: "disk_io", Description: "no space", Path: "/tmp/x"},
			"no space (at /tmp/x)",
		},
		{
			engine.ExportErrorEvent{Description: "plain failure"},
			"plain failure",
		},
	}
	for _, tc := range cases {
		if got := exportErrorText(tc.ev); got != tc.want {
			t.Errorf("exportErrorText(%+v) = %q, want %q", tc.ev, got, tc.want)
		}
	}
}

func TestExportSettingsFromChecks(t *testing.T) {
	checked := map[string]bool{
		"personal_info": true, "contacts": true, "media_photos": true,
	}
	s := exportSettingsFromChecks(checked, 512)
	if !s.PersonalInfo || !s.Contacts {
		t.Error("personal_info/contacts not mapped")
	}
	if !s.MediaPhotos {
		t.Error("media_photos not mapped")
	}
	if s.Stories || s.Sessions || s.PersonalChats || s.MediaGif {
		t.Error("unchecked options leaked into settings")
	}
	if s.SizeLimitMB != 512 {
		t.Errorf("SizeLimitMB = %d, want 512", s.SizeLimitMB)
	}
}

func TestContentDialogSurfaceExport(t *testing.T) {
	f := frame{exportDlg: &exportDlgState{}}
	if got := contentDialogSurface(f); got != "export" {
		t.Errorf("contentDialogSurface with exportDlg = %q, want export", got)
	}
}

func TestEscTargetExportDlgSelfHandled(t *testing.T) {
	f := frame{exportDlg: &exportDlgState{}, menu: &menuTarget{}}
	if got := escTarget(f); got != "" {
		t.Errorf("exportDlg + menu: escTarget = %q, want empty (dialog consumes Esc)", got)
	}
}
