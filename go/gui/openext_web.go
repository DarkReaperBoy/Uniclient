//go:build js

package gui

// Web opener: tapped links open a new browser tab via window.open (the
// js call runs synchronously so the user-activation context is kept for
// popup blocking). Local paths have no web equivalent — the engine never
// materializes media files under js anyway.

import (
	"syscall/js"
)

func init() {
	openExternalAsync = func(target string, done func(error)) {
		if u, ok := sanitizeURL(target); ok {
			if w := js.Global().Get("window"); w != js.Undefined() && w != js.Null() {
				w.Call("open", u, "_blank")
				if done != nil {
					done(nil)
				}
				return
			}
		}
		if done != nil {
			done(errNoOpener)
		}
	}
	revealAsync = func(path string, done func(error)) {
		if done != nil {
			done(errNoOpener)
		}
	}
}
