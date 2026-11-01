//go:build android

package audio

import (
	"gioui.org/app"
)

func SetAndroidViewEvent(ev any) {
	if av, ok := ev.(app.AndroidViewEvent); ok {
		jniState.mu.Lock()
		if av.View != 0 {
			jniState.view = av.View
			jniState.jvm = app.JavaVM()
		} else {
			jniState.view = 0
		}
		jniState.mu.Unlock()
	}
}
