package gui

import (
	"testing"

	"uniclient/engine"
	"uniclient/utils"
)

// Similar-channels AyuGram settings (slice 169, primary source:
// AyuGramDesktop ayu_settings.h — hideSimilarChannels (default false) +
// collapseSimilarChannels (default TRUE) — plus the per-chat expanded
// state, tdesktop's ChannelDataFlag::SimilarExpanded parity).

// TestSimilarBlockMode pins the pure render decision: hide wins over
// everything, collapse renders the compact bar, otherwise the full card
// row.
func TestSimilarBlockMode(t *testing.T) {
	cases := []struct {
		hide, collapsed bool
		want            string
	}{
		{false, false, "expanded"},
		{false, true, "collapsed"},
		{true, false, "off"},
		{true, true, "off"}, // hide beats collapse
	}
	for _, c := range cases {
		if got := similarBlockMode(c.hide, c.collapsed); got != c.want {
			t.Errorf("similarBlockMode(%v, %v) = %q, want %q", c.hide, c.collapsed, got, c.want)
		}
	}
}

// TestSimilarExpandedDefault pins AyuGram's collapse default semantics:
// collapse-config ON (the default) means channels start collapsed, so the
// expanded default is false.
func TestSimilarExpandedDefault(t *testing.T) {
	if similarExpandedDefault(true) {
		t.Errorf("collapse on: channels start collapsed, expanded default must be false")
	}
	if !similarExpandedDefault(false) {
		t.Errorf("collapse off: channels start expanded, expanded default must be true")
	}
}

// TestSimilarCollapseEffective pins the *bool config resolution: nil =
// collapsed (AyuGram ships collapse ON by default).
func TestSimilarCollapseEffective(t *testing.T) {
	if !utils.EffectiveCollapseSimilar(utils.AppConfig{}) {
		t.Errorf("nil config must collapse (AyuGram default ON)")
	}
	v := true
	if !utils.EffectiveCollapseSimilar(utils.AppConfig{AyuCollapseSimilarChannels: &v}) {
		t.Errorf("explicit true must collapse")
	}
	v = false
	if utils.EffectiveCollapseSimilar(utils.AppConfig{AyuCollapseSimilarChannels: &v}) {
		t.Errorf("explicit false must not collapse")
	}
}

// TestSimilarEffectiveExpanded pins the per-chat state resolution: an
// explicit toggle beats the config default; absent falls back to it
// (tdesktop's runtime SimilarExpanded flag over AyuGram's default).
func TestSimilarEffectiveExpanded(t *testing.T) {
	m := map[string]bool{"a|c1": true, "a|c2": false}
	if !similarEffectiveExpanded(m, "a|c1", false) {
		t.Errorf("explicit expanded must win over the collapsed default")
	}
	if similarEffectiveExpanded(m, "a|c2", true) {
		t.Errorf("explicit collapsed must win over the expanded default")
	}
	if !similarEffectiveExpanded(m, "a|c3", true) {
		t.Errorf("absent entry falls back to the expanded default")
	}
	if similarEffectiveExpanded(m, "a|c3", false) {
		t.Errorf("absent entry falls back to the collapsed default")
	}
}

// TestAppendSimilarRowModes pins the row-model integration: hide drops the
// row entirely, collapse renders the compact row, default renders the full
// block row.
func TestAppendSimilarRowModes(t *testing.T) {
	chan_ := &engine.ChatInfo{AccountID: "a", ChatID: "1", Type: engine.ChatTypeChanVal}
	base := []chatRow{{msgIdx: 0}}

	if rows := appendSimilarRow(base, chan_, "", 3, true, false); len(rows) != 1 {
		t.Errorf("hide must drop the row, got %d rows", len(rows))
	}
	rows := appendSimilarRow(base, chan_, "", 3, false, true)
	if len(rows) != 2 || !rows[1].simCollapsed || rows[1].simBlock {
		t.Errorf("collapse must append the compact row, got %+v", rows[1:])
	}
	rows = appendSimilarRow(base, chan_, "", 3, false, false)
	if len(rows) != 2 || !rows[1].simBlock || rows[1].simCollapsed {
		t.Errorf("default must append the block row, got %+v", rows[1:])
	}
	// No recommendations or non-channel chats never append either way.
	if rows := appendSimilarRow(base, chan_, "", 0, false, true); len(rows) != 1 {
		t.Errorf("zero recommendations must drop the row")
	}
	dm := &engine.ChatInfo{AccountID: "a", ChatID: "2", Type: engine.ChatTypeDMVal}
	if rows := appendSimilarRow(base, dm, "", 5, false, true); len(rows) != 1 {
		t.Errorf("DM chats must drop the row")
	}
}

// TestConfigFieldChangesSimilar covers the new Ayu toggle keys through the
// settings' config-fieldChanges mapping.
func TestConfigFieldChangesSimilar(t *testing.T) {
	c := configFieldChanges("ayu_hide_similar_channels", true)
	if c == nil || c.AyuHideSimilarChannels == nil || !*c.AyuHideSimilarChannels {
		t.Fatal("ayu_hide_similar_channels(true): missing change")
	}
	c = configFieldChanges("ayu_hide_similar_channels", false)
	if c == nil || c.AyuHideSimilarChannels == nil || *c.AyuHideSimilarChannels {
		t.Fatal("ayu_hide_similar_channels(false): missing change")
	}
	c = configFieldChanges("ayu_collapse_similar_channels", false)
	if c == nil || c.AyuCollapseSimilarChannels == nil || *c.AyuCollapseSimilarChannels {
		t.Fatal("ayu_collapse_similar_channels(false): missing change")
	}
	c = configFieldChanges("ayu_collapse_similar_channels", true)
	if c == nil || c.AyuCollapseSimilarChannels == nil || !*c.AyuCollapseSimilarChannels {
		t.Fatal("ayu_collapse_similar_channels(true): missing change")
	}
}
