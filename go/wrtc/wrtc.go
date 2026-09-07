// Package wrtc is a thin compatibility layer over github.com/pion/webrtc/v4
// that lets the cores' call transports compile for BOTH native platforms and
// js/wasm.
//
// Why it exists: pion/webrtc v4 has two different API surfaces. On native
// platforms the full media API is available (PeerConnection.AddTrack/OnTrack/
// GetStats/GetSenders, TrackLocalStaticRTP/TrackLocalStaticSample, MediaEngine,
// interceptor configuration). On GOOS=js the library wraps the browser's
// WebRTC instead, and that native-media surface does not exist.
//
// On native platforms every wrtc symbol is a type/func alias straight to
// pion/webrtc — zero runtime cost, one code path, no behavior change.
// On js/wasm the same names are compile-only stubs: constructors that build
// media plumbing return ErrUnsupported, signaling methods on the wrapped
// browser PeerConnection keep working (the pattern the bale core already
// established with bale_calls_js.go — signaling works, media degrades).
//
// The cores import wrtc instead of webrtc ONLY for the symbols below;
// everything pion provides on both platforms is still imported as
// webrtc.X directly from the cores.
package wrtc
