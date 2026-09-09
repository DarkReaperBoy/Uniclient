//go:build !js && !android

package gui

// Desktop opener (linux/darwin/windows): spawn the platform command and
// reap it — Run waits for the child, so no zombie openers accumulate.
// xdg-open / open / rundll32 all return after delegating to the real
// handler, so the wait is short.

import (
	"os/exec"
	"runtime"
)

func init() {
	openExternalAsync = func(target string, done func(error)) {
		prog, args := openArgsFor(runtime.GOOS, target)
		if prog == "" {
			if done != nil {
				done(errNoOpener)
			}
			return
		}
		go func() {
			if done != nil {
				done(exec.Command(prog, args...).Run())
			}
		}()
	}
	revealAsync = func(path string, done func(error)) {
		prog, args := revealArgsFor(runtime.GOOS, path)
		if prog == "" {
			if done != nil {
				done(errNoOpener)
			}
			return
		}
		go func() {
			if done != nil {
				done(exec.Command(prog, args...).Run())
			}
		}()
	}
}
