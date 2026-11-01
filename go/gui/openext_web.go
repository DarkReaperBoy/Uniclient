//go:build js

package gui

import (
	"syscall/js"
)

func init() {
	openExternalAsync = func(target string, done func(error)) {
		if u, ok := sanitizeURL(target); ok {
			if w := js.Global().Get("window"); w.Type() != js.TypeUndefined && w.Type() != js.TypeNull {
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
