//go:build js

package audio

import "sync"

func (w *WebDevice) ForTestMu() *sync.Mutex {
	return &w.mu
}
