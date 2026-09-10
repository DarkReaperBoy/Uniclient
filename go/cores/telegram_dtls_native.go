//go:build !js

package cores

import (
	"fmt"
	"time"

	"github.com/pion/webrtc/v4"

	"uniclient/wrtc"
)

// monitorCallDTLS logs DTLS transport state transitions for an active call.
// Native-only: the js/wasm DTLSTransport has no OnStateChange/State.
func monitorCallDTLS(pc *wrtc.PeerConnection, t0 time.Time) {
	if pc == nil {
		return
	}
	sctp := pc.SCTP()
	if sctp == nil {
		return
	}
	dtlsT := sctp.Transport()
	if dtlsT == nil {
		return
	}
	dtlsT.OnStateChange(func(state webrtc.DTLSTransportState) {
		fmt.Printf("[tg-call] DTLS state: %s (+%dms)\n", state, time.Since(t0).Milliseconds())
	})
	fmt.Printf("[tg-call] DTLS initial state: %s\n", dtlsT.State())
}
