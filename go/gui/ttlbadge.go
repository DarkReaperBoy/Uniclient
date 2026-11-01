package gui

import (
	"bytes"
	"encoding/json"
	"strconv"

	"gioui.org/layout"
	"gioui.org/unit"

	"uniclient/engine"
)

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

func oneTimeChipVisible(mediaType, mediaTTL int) bool {
	return mediaTTL > 0 && oneTimeLabel(mediaType) != ""
}

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
