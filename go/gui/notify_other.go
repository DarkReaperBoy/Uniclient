//go:build !linux && !windows

package gui

func notifyDesktop(title, body, key, icon string, actions []string, onAction func(string)) error {
	return nil
}
