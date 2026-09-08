package gui

import (
	"time"
)

// Login-code relay (AyuGram parity slice 31).
//
// When a new account is logging in and any connected account receives the
// Telegram login-code message, the engine broadcasts EventLoginCode. The
// login view shows the code in a banner and auto-fills the OTP field,
// like AyuGram's handleLoginCode.

// loginCodeFresh reports whether a relayed code is still usable.
// Telegram codes stay valid for a while; 10 minutes is the AyuGram window.
func loginCodeFresh(code string, at, now time.Time) bool {
	return code != "" && !at.IsZero() && now.Sub(at) < 10*time.Minute
}

// loginCodeBannerText renders the banner caption (AyuGram wording).
func loginCodeBannerText(code string) string {
	return "Code from your other account: " + code
}
