//go:build !windows

package gui

// instance_stub.go — slice 202: platforms without the toast
// click-through channel. Linux notifications click through the
// freedesktop default action (notify_linux.go); wasm/android have no
// OS notification surface to activate. Entry points are no-ops so call
// sites stay unconditional.

// HandleLaunchURI: no launch URIs on this platform.
func HandleLaunchURI(args []string, configDir string) bool { return false }

// ServeInstanceCommands: no command channel on this platform.
func (a *App) ServeInstanceCommands(configDir string) {}

// stopInstanceServer: nothing to stop.
func stopInstanceServer() {}
