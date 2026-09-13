package gui

import (
	"testing"
)

// Boosts page (slice 192, parity row "Giveaways / boosts" — tdesktop's
// boost info box): pure logic — level/progress composition from the status
// map, booster row labels, list paging, own-boost gating. Layout verified
// by compile + review (repo discipline).

func boostStatusFixture(level, boosts, curLevel, nextLevel, gift int, myBoost bool) map[string]interface{} {
	return map[string]interface{}{
		"level":                level,
		"boosts":               boosts,
		"current_level_boosts": curLevel,
		"next_level_boosts":    nextLevel,
		"gift_boosts":          gift,
		"my_boost":             myBoost,
		"boost_url":            "https://t.me/boost/abc",
	}
}

func TestBoostLevelLabel(t *testing.T) {
	if got := boostLevelLabel(boostStatusFixture(3, 12, 10, 40, 0, false)); got != "Level 3" {
		t.Errorf("boostLevelLabel = %q, want Level 3", got)
	}
	if got := boostLevelLabel(map[string]interface{}{}); got != "Level 0" {
		t.Errorf("empty status label = %q, want Level 0", got)
	}
}

func TestBoostProgressFraction(t *testing.T) {
	// 12 boosts, current level at 10, next level at 40 → 2/30.
	f := boostStatusFixture(3, 12, 10, 40, 0, false)
	if got := boostProgressFraction(f); got < 0.066 || got > 0.067 {
		t.Errorf("boostProgressFraction = %v, want ~0.0667", got)
	}
	// Degenerate: no next level (max) → full bar.
	f2 := boostStatusFixture(9, 500, 400, 400, 0, false)
	if got := boostProgressFraction(f2); got != 1 {
		t.Errorf("max-level fraction = %v, want 1", got)
	}
	// Missing fields → 0.
	if got := boostProgressFraction(map[string]interface{}{}); got != 0 {
		t.Errorf("empty fraction = %v, want 0", got)
	}
}

func TestBoostToNextLabel(t *testing.T) {
	f := boostStatusFixture(3, 12, 10, 40, 0, false)
	if got := boostToNextLabel(f); got != "28 boosts to Level 4" {
		t.Errorf("boostToNextLabel = %q, want 28 boosts to Level 4", got)
	}
	// Maxed: no next level.
	f2 := boostStatusFixture(9, 500, 400, 400, 0, false)
	if got := boostToNextLabel(f2); got != "Max level reached" {
		t.Errorf("maxed label = %q, want Max level reached", got)
	}
}

func TestBoosterRowLabel(t *testing.T) {
	row := map[string]interface{}{
		"user_name":  "Alice",
		"multiplier": 3,
		"gift":       true,
	}
	if got := boosterRowTitle(row); got != "Alice" {
		t.Errorf("boosterRowTitle = %q, want Alice", got)
	}
	if got := boosterRowTitle(map[string]interface{}{"user_id": int64(7)}); got != "user 7" {
		t.Errorf("fallback title = %q, want user 7", got)
	}
	sub := boosterRowSub(row)
	if sub == "" {
		t.Error("boosterRowSub with multiplier+gift should not be empty")
	}
	// Multiplier chip renders ×3.
	if !containsStr(boosterRowSub(row), "3") {
		t.Errorf("boosterRowSub = %q, want multiplier mention", sub)
	}
}

func TestBoostListRowsPaging(t *testing.T) {
	// hasMore: next_offset present + count beyond loaded rows.
	list := map[string]interface{}{
		"count":       60,
		"next_offset": "offset2",
		"boosters": []interface{}{
			map[string]interface{}{"user_name": "A"},
			map[string]interface{}{"user_name": "B"},
		},
	}
	rows, next, total, more := boostListFields(list)
	if len(rows) != 2 || next != "offset2" || total != 60 || !more {
		t.Errorf("boostListFields = %d/%q/%d/%v", len(rows), next, total, more)
	}
	// No offset → no more pages even with count > rows.
	list2 := map[string]interface{}{
		"count":    10,
		"boosters": []interface{}{map[string]interface{}{"user_name": "A"}},
	}
	_, next2, _, more2 := boostListFields(list2)
	if next2 != "" || more2 {
		t.Errorf("no-offset list should not page: next=%q more=%v", next2, more2)
	}
}

func containsStr(s, sub string) bool {
	return len(s) >= len(sub) && (s == sub || len(s) > 0 && indexStr(s, sub) >= 0)
}

func indexStr(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}
