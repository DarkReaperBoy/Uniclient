//go:build !android

// SPDX-License-Identifier: Unlicense OR MIT

package audio

// SetAndroidViewEvent is a no-op everywhere except Android (see
// view_android.go). It accepts the raw event to avoid importing gio here.
func SetAndroidViewEvent(ev any) {}
