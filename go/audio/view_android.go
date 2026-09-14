//go:build android

// SPDX-License-Identifier: Unlicense OR MIT

package audio

import (
	"gioui.org/app"
)

// SetAndroidViewEvent captures the Android view handle + JavaVM from the
// gio ViewEvent stream. The GUI layer calls it for every window event; on
// Android the event carries a JNI global reference to the android.view.View
// backing the window (app.AndroidViewEvent), and app.JavaVM() exposes the
// process JVM. Both feed the JNI permission flow in jni_android.go.
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
