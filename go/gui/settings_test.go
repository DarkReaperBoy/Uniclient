package gui

import (
	"testing"

	"uniclient/engine"
)

// Settings shell (AyuGram parity §8): section rail + real engine-backed
// pages. Tests lock the section list, cache-tag labels, and the
// field→ConfigChanges / GhostFlags mappings before the widgets.

func TestSettingsSections(t *testing.T) {
	want := []string{
		"Main", "Notifications", "Privacy & Security", "Data & Storage",
		"Appearance", "Ayu", "About",
	}
	if len(settingsSections) != len(want) {
		t.Fatalf("settingsSections len = %d, want %d", len(settingsSections), len(want))
	}
	for i, w := range want {
		if settingsSections[i] != w {
			t.Errorf("settingsSections[%d] = %q, want %q", i, settingsSections[i], w)
		}
	}
}

func TestCacheTagLabels(t *testing.T) {
	want := [6]string{"Images", "Stickers", "Voice messages", "Video messages", "Animations", "Media cache"}
	for i, w := range want {
		if got := cacheTagLabel(i); got != w {
			t.Errorf("cacheTagLabel(%d) = %q, want %q", i, got, w)
		}
	}
	if got := cacheTagLabel(6); got != "" {
		t.Errorf("cacheTagLabel(6) = %q, want empty", got)
	}
}

func TestConfigFieldChanges(t *testing.T) {
	fields := []struct {
		field string
		get   func(*engine.ConfigChanges) *bool
	}{
		{"send_read_receipts", func(c *engine.ConfigChanges) *bool { return c.SendReadReceipts }},
		{"send_typing", func(c *engine.ConfigChanges) *bool { return c.SendTyping }},
		{"send_upload_progress", func(c *engine.ConfigChanges) *bool { return c.SendUploadProgress }},
		{"send_read_stories", func(c *engine.ConfigChanges) *bool { return c.SendReadStories }},
		{"send_online_packets", func(c *engine.ConfigChanges) *bool { return c.SendOnlinePackets }},
		{"send_offline_after_online", func(c *engine.ConfigChanges) *bool { return c.SendOfflineAfterOnline }},
		{"mark_read_after_action", func(c *engine.ConfigChanges) *bool { return c.MarkReadAfterAction }},
		{"use_scheduled_messages", func(c *engine.ConfigChanges) *bool { return c.UseScheduledMessages }},
		{"send_without_sound", func(c *engine.ConfigChanges) *bool { return c.SendWithoutSound }},
		{"notify_dms", func(c *engine.ConfigChanges) *bool { return c.NotifyDMs }},
		{"notify_groups", func(c *engine.ConfigChanges) *bool { return c.NotifyGroups }},
		{"notify_mentions_only", func(c *engine.ConfigChanges) *bool { return c.NotifyMentionsOnly }},
	}
	for _, f := range fields {
		c := configFieldChanges(f.field, true)
		if c == nil {
			t.Fatalf("configFieldChanges(%q) = nil", f.field)
		}
		if p := f.get(c); p == nil || !*p {
			t.Errorf("configFieldChanges(%q, true) did not set field", f.field)
		}
		c2 := configFieldChanges(f.field, false)
		if p := f.get(c2); p == nil || *p {
			t.Errorf("configFieldChanges(%q, false) did not clear field", f.field)
		}
	}
	if c := configFieldChanges("bogus", true); c != nil {
		t.Errorf("configFieldChanges(bogus) = %v, want nil", c)
	}
}

func TestGhostFlagSet(t *testing.T) {
	fields := []struct {
		field string
		set   func(g *engine.GhostFlags, v bool)
		get   func(g engine.GhostFlags) bool
	}{
		{"send_read_receipts", func(g *engine.GhostFlags, v bool) { g.SendReadReceipts = v }, func(g engine.GhostFlags) bool { return g.SendReadReceipts }},
		{"send_upload_progress", func(g *engine.GhostFlags, v bool) { g.SendUploadProgress = v }, func(g engine.GhostFlags) bool { return g.SendUploadProgress }},
		{"send_read_stories", func(g *engine.GhostFlags, v bool) { g.SendReadStories = v }, func(g engine.GhostFlags) bool { return g.SendReadStories }},
		{"send_online_packets", func(g *engine.GhostFlags, v bool) { g.SendOnlinePackets = v }, func(g engine.GhostFlags) bool { return g.SendOnlinePackets }},
		{"send_offline_after_online", func(g *engine.GhostFlags, v bool) { g.SendOfflineAfterOnline = v }, func(g engine.GhostFlags) bool { return g.SendOfflineAfterOnline }},
		{"mark_read_after_action", func(g *engine.GhostFlags, v bool) { g.MarkReadAfterAction = v }, func(g engine.GhostFlags) bool { return g.MarkReadAfterAction }},
		{"use_scheduled_messages", func(g *engine.GhostFlags, v bool) { g.UseScheduledMessages = v }, func(g engine.GhostFlags) bool { return g.UseScheduledMessages }},
		{"send_without_sound", func(g *engine.GhostFlags, v bool) { g.SendWithoutSound = v }, func(g engine.GhostFlags) bool { return g.SendWithoutSound }},
	}
	for _, f := range fields {
		g := engine.GhostFlags{}
		if !ghostFlagSet(&g, f.field, true) {
			t.Fatalf("ghostFlagSet(%q) = false", f.field)
		}
		if !f.get(g) {
			t.Errorf("ghostFlagSet(%q, true) did not set field", f.field)
		}
		ghostFlagSet(&g, f.field, false)
		if f.get(g) {
			t.Errorf("ghostFlagSet(%q, false) did not clear field", f.field)
		}
	}
	if ghostFlagSet(&engine.GhostFlags{}, "bogus", true) {
		t.Error("ghostFlagSet(bogus) = true, want false")
	}
}

func TestThemeName(t *testing.T) {
	if got := themeName(true); got != "light" {
		t.Errorf("themeName(true) = %q, want light", got)
	}
	if got := themeName(false); got != "dark" {
		t.Errorf("themeName(false) = %q, want dark", got)
	}
}
