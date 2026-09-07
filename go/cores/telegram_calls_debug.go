//go:build !js

package cores

import (
	"fmt"

	"github.com/pion/webrtc/v4"
)

// logCallTransceivers dumps the transceiver table of an active call for
// debugging (called from OnTrack). Native-only: the js/wasm transceiver API
// lacks Mid() and Receiver().Track().
func logCallTransceivers(call *tgCall) {
	if call == nil || call.pc == nil {
		return
	}
	for i, tr := range call.pc.GetTransceivers() {
		mid := tr.Mid()
		dir := tr.Direction()
		var recvSSRC webrtc.SSRC
		if tr.Receiver() != nil && tr.Receiver().Track() != nil {
			recvSSRC = tr.Receiver().Track().SSRC()
		}
		fmt.Printf("[tg-call]   transceiver[%d]: mid=%s dir=%s recvSSRC=%d\n", i, mid, dir, recvSSRC)
	}
}
