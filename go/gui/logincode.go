package gui

import (
	"time"
)

func loginCodeFresh(code string, at, now time.Time) bool {
	return code != "" && !at.IsZero() && now.Sub(at) < 10*time.Minute
}

func loginCodeBannerText(code string) string {
	return "Code from your other account: " + code
}
