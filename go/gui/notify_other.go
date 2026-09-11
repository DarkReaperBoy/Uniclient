//go:build !linux

package gui

// notifyDesktop is a no-op where Freedesktop banners don't exist
// (windows, wasm, android). The notification gating logic still runs, so
// wiring a platform layer later is a drop-in; onAction is never invoked
// (there is no banner to click).
func notifyDesktop(title, body, key, icon string, actions []string, onAction func(string)) error {
	return nil
}
