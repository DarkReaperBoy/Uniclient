//go:build js

package cores

import (
	"errors"
	"fmt"
)

var ErrWasmCallsUnsupported = errors.New("bale calls are not supported on web (wasm) builds")

func (c *baleActiveCall) audioPubSetMuted(muted bool) {}

func (b *BaleCore) baleConnectLiveKit(session *CallSession) error {
	return fmt.Errorf("%w: %s (room=%s)", ErrWasmCallsUnsupported, session.ID, session.Meta["room"])
}

func (b *BaleCore) baleDisconnectLiveKit() {}
