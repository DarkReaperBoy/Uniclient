package gui

import (
	"testing"

	"uniclient/utils"
)

func TestAvatarCornerRadiusPx(t *testing.T) {
	cases := []struct {
		corners, size, want int
	}{
		{0, 52, 0},
		{23, 52, 26},
		{12, 52, 13},
		{1, 46, 1},
		{11, 46, 11},
		{23, 40, 20},
		{5, 30, 3},
	}
	for _, c := range cases {
		if got := avatarCornerRadiusPx(c.corners, c.size); got != c.want {
			t.Errorf("avatarCornerRadiusPx(%d, %d) = %d, want %d", c.corners, c.size, got, c.want)
		}
	}
	if got := avatarCornerRadiusPx(-3, 52); got != 0 {
		t.Errorf("negative corners = %d, want 0 (square)", got)
	}
	if got := avatarCornerRadiusPx(99, 52); got != 26 {
		t.Errorf("oversized corners = %d, want 26 (circle)", got)
	}
}

func TestAvatarCornersLabel(t *testing.T) {
	if s := avatarCornersLabel(0); s != "SQUARE" {
		t.Errorf("label(0) = %q, want SQUARE", s)
	}
	if s := avatarCornersLabel(23); s != "CIRCLE" {
		t.Errorf("label(23) = %q, want CIRCLE", s)
	}
	if s := avatarCornersLabel(12); s != "12" {
		t.Errorf("label(12) = %q, want 12", s)
	}
	if s := avatarCornersLabel(1); s != "1" {
		t.Errorf("label(1) = %q, want 1", s)
	}
}

func TestForumAvatarRadiusPx(t *testing.T) {
	cases := []struct{ size, want int }{
		{52, 15},
		{40, 12},
		{46, 13},
	}
	for _, c := range cases {
		if got := forumAvatarRadiusPx(c.size); got != c.want {
			t.Errorf("forumAvatarRadiusPx(%d) = %d, want %d", c.size, got, c.want)
		}
	}
}

func TestChatAvatarCornerRadius(t *testing.T) {
	if got := chatAvatarCornerRadius(0, false, false, 52); got != 0 {
		t.Errorf("non-forum square = %d, want 0", got)
	}
	if got := chatAvatarCornerRadius(23, false, false, 52); got != 26 {
		t.Errorf("non-forum circle = %d, want 26", got)
	}
	if got := chatAvatarCornerRadius(0, false, true, 52); got != 15 {
		t.Errorf("forum + slider 0 + single off = %d, want 15 (native)", got)
	}
	if got := chatAvatarCornerRadius(23, false, true, 52); got != 15 {
		t.Errorf("forum + slider 23 + single off = %d, want 15 (native)", got)
	}
	if got := chatAvatarCornerRadius(23, true, true, 52); got != 26 {
		t.Errorf("forum + slider 23 + single on = %d, want 26", got)
	}
	if got := chatAvatarCornerRadius(0, true, true, 52); got != 0 {
		t.Errorf("forum + slider 0 + single on = %d, want 0", got)
	}
}

func TestAvatarCornersSliderMapping(t *testing.T) {
	if v := avatarCornersFromSlider(0); v != 0 {
		t.Errorf("slider 0.0 = %d, want 0", v)
	}
	if v := avatarCornersFromSlider(1); v != 23 {
		t.Errorf("slider 1.0 = %d, want 23", v)
	}
	if v := avatarCornersFromSlider(0.5); v != 12 {
		t.Errorf("slider 0.5 = %d, want 12", v)
	}
}

func TestCfgFromAppConfigAvatarCorners(t *testing.T) {
	snap := cfgFromAppConfig(&utils.AppConfig{})
	if snap.AyuAvatarCorners != 23 {
		t.Errorf("default corners = %d, want 23", snap.AyuAvatarCorners)
	}
	if snap.AyuSingleCornerRadius {
		t.Error("default single corner radius = true, want false")
	}
	c12, single := 12, true
	snap = cfgFromAppConfig(&utils.AppConfig{AyuAvatarCorners: &c12, AyuSingleCornerRadius: &single})
	if snap.AyuAvatarCorners != 12 || !snap.AyuSingleCornerRadius {
		t.Fatalf("snapshot = %d/%v, want 12/true", snap.AyuAvatarCorners, snap.AyuSingleCornerRadius)
	}
}

func TestEffectiveAvatarCorners(t *testing.T) {
	if v := utils.EffectiveAvatarCorners(utils.AppConfig{}); v != 23 {
		t.Errorf("nil = %d, want 23", v)
	}
	c7 := 7
	if v := utils.EffectiveAvatarCorners(utils.AppConfig{AyuAvatarCorners: &c7}); v != 7 {
		t.Errorf("7 = %d, want 7", v)
	}
	c99 := 99
	if v := utils.EffectiveAvatarCorners(utils.AppConfig{AyuAvatarCorners: &c99}); v != 23 {
		t.Errorf("99 = %d, want 23 (clamped)", v)
	}
}

func TestAvatarCornersPreviewRowState(t *testing.T) {
	st := newAvatarCornersPreview(23)
	if st.title != "Uniclient Releases" || st.sub != "Better late than never" {
		t.Fatalf("preview text = %q/%q", st.title, st.sub)
	}
	if st.radiusPx(52) != 26 {
		t.Errorf("preview radius at 23 = %d, want 26", st.radiusPx(52))
	}
	st = newAvatarCornersPreview(0)
	if st.radiusPx(52) != 0 {
		t.Errorf("preview radius at 0 = %d, want 0", st.radiusPx(52))
	}
}
