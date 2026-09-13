//go:build !linux && !windows

package gui

// notifyDesktop is a no-op where neither Freedesktop banners nor
// WinRT toasts exist (wasm, android). Windows has its own transport
// (notify_windows.go). The notification gating logic still runs, so
// wiring a platform layer later is a drop-in; onAction is never invoked
// (there is no banner to click).
func notifyDesktop(title, body, key, icon string, actions []string, onAction func(string)) error {
	return nil
}
