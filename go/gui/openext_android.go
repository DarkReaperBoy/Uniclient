//go:build android

package gui

func init() {
	openExternalAsync = func(target string, done func(error)) {
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
