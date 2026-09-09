//go:build android

package gui

// Android opener: no shims yet (a JNI intent bridge is future work), so
// every handoff fails honestly and callers fall back (links copy to the
// clipboard; media keeps the "Saved to" toast path).

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
