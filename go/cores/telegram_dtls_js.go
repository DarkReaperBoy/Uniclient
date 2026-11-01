//go:build js

package cores

import (
	"time"

	"uniclient/wrtc"
)

func monitorCallDTLS(_ *wrtc.PeerConnection, _ time.Time) {}
