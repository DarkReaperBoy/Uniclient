//go:build js

package cores

import (
	"time"

	"uniclient/wrtc"
)

// monitorCallDTLS is a no-op on js/wasm: the browser owns DTLS and its
// transport state is not surfaced to Go.
func monitorCallDTLS(_ *wrtc.PeerConnection, _ time.Time) {}
