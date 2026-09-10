//go:build !linux

package gui

// notifyDesktop is a no-op where Freedesktop banners don't exist
// (windows, wasm, android). The notification gating logic still runs, so
// wiring a platform layer later is a drop-in.
func notifyDesktop(title, body string) error { return nil }
