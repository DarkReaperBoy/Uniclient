//go:build js

package cores

// logCallTransceivers is a no-op on js/wasm: the browser-backed transceiver
// API has no Mid()/Receiver().Track(), and OnTrack never fires there anyway.
func logCallTransceivers(call *tgCall) {}
