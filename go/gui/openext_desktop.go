//go:build !js && !android

package gui

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
