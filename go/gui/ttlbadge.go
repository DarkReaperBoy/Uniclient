package gui

import (
	"bytes"
	"encoding/json"
	"strconv"

	"gioui.org/layout"
	"gioui.org/unit"

	"uniclient/engine"
)

// TTL badges (slice 182, parity row "Expired/self-destruct media" —
// tdesktop's one-time media + auto-delete timer chrome): media with a
// self-destruct TTL (media_ttl_seconds, the one-time photo/video/voice
// flow — the server destroys the media after the view) renders the
// "One-time …" chip above the media block; messages in auto-delete
// chats (ttl_seconds) render a timer glyph + period beside the
// timestamp. Both read the cached Extra the telegram core already
// writes — no new RPCs.

// parseTTLExtras returns (message auto-delete period, media one-time
// TTL) from the cached Extra. Pure — unit-tested.
func parseTTLExtras(m *engine.CachedMessage) (msgTTL, mediaTTL int) {
	if m == nil || len(m.ContentRaw) == 0 {
		return 0, 0
	}
	if !bytes.Contains(m.ContentRaw, []byte(`ttl_seconds`)) {
		return 0, 0
	}
	var env struct {
		Extra map[string]interface{} `json:"extra"`
	}
	if err := json.Unmarshal(m.ContentRaw, &env); err != nil || env.Extra == nil {
		return 0, 0
	}
	if f, ok := env.Extra["ttl_seconds"].(float64); ok {
		msgTTL = int(f)
	}
	if f, ok := env.Extra["media_ttl_seconds"].(float64); ok {
		mediaTTL = int(f)
	}
	return msgTTL, mediaTTL
}

// fmtTTLPeriod renders an auto-delete period compactly: 30s / 5m / 2h /
// 1d / 1w. Pure — unit-tested.
func fmtTTLPeriod(sec int) string {
	switch {
	case sec <= 0:
		return ""
	case sec < 60:
		return strconv.Itoa(sec) + "s"
	case sec < 3600:
		if sec%60 == 0 {
			return strconv.Itoa(sec/60) + "m"
		}
		return strconv.Itoa(sec/60) + "m"
	case sec < 86400:
		if sec%3600 == 0 {
			return strconv.Itoa(sec/3600) + "h"
		}
		return strconv.Itoa(sec/3600) + "h"
	case sec < 604800:
		if sec%86400 == 0 {
			return strconv.Itoa(sec/86400) + "d"
		}
		return strconv.Itoa(sec/86400) + "d"
	default:
		if sec%604800 == 0 {
			return strconv.Itoa(sec/604800) + "w"
		}
		return strconv.Itoa(sec/604800) + "w"
	}
}

// oneTimeLabel: the one-time chip's label (tdesktop's notificationText
// variants). "" for media kinds without a one-time flow. Pure.
func oneTimeLabel(mediaType int) string {
	switch mediaType {
	case engine.MediaImage:
		return "One-time photo"
	case engine.MediaVideo:
		return "One-time video"
	case engine.MediaVoice:
		return "One-time voice message"
	case engine.MediaVideoNote:
		return "One-time video message"
	default:
		return ""
	}
}

// oneTimeChipVisible: the chip shows only for one-time-able media kinds
// carrying a media TTL. Pure.
func oneTimeChipVisible(mediaType, mediaTTL int) bool {
	return mediaTTL > 0 && oneTimeLabel(mediaType) != ""
}

// layoutOneTimeChip renders the one-time media chip above the media
// block: timer glyph + label (accent, like tdesktop's one-time chrome).
func (a *App) layoutOneTimeChip(gtx layout.Context, mediaType int) layout.Dimensions {
	label := oneTimeLabel(mediaType)
	if label == "" {
		return layout.Dimensions{}
	}
	return layout.Inset{Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.SurfaceHi, unit.Dp(10), func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(8), Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							gtx.Constraints.Max.X = gtx.Dp(unit.Dp(14))
							gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(14))
							return iconActionSchedule.Layout(gtx, a.ui.p.Accent)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(11), label)
						lbl.Color = a.ui.p.Accent
						return lbl.Layout(gtx)
					}),
				)
			})
		})
	})
}

// layoutTTLTimer renders the auto-delete timer chip in the meta row:
// timer glyph + period text.
func (a *App) layoutTTLTimer(gtx layout.Context, period int) layout.Dimensions {
	txt := fmtTTLPeriod(period)
	if txt == "" {
		return layout.Dimensions{}
	}
	return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Right: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					gtx.Constraints.Max.X = gtx.Dp(unit.Dp(12))
					gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(12))
					return iconActionSchedule.Layout(gtx, a.ui.p.TextFaint)
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(10), txt)
				return lbl.Layout(gtx)
			}),
		)
	})
}
