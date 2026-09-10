//go:build js

// js/wasm stub for the Bale call transport.
//
// The LiveKit server SDK does not compile for js/wasm, so calling is
// unsupported on the web target. The signaling methods (StartCall,
// JoinGroupCall, EndCall) in bale.go still work — they just get an
// ErrNotSupported from the transport connection step.

package cores

import (
	"errors"
	"fmt"
)

// ErrWasmCallsUnsupported is returned by the Bale call transport on js/wasm.
var ErrWasmCallsUnsupported = errors.New("bale calls are not supported on web (wasm) builds")

// audioPubSetMuted is a no-op: there is never an active transport on js/wasm.
func (c *baleActiveCall) audioPubSetMuted(muted bool) {}

// baleConnectLiveKit always fails on js/wasm — there is no LiveKit transport.
func (b *BaleCore) baleConnectLiveKit(session *CallSession) error {
	return fmt.Errorf("%w: %s (room=%s)", ErrWasmCallsUnsupported, session.ID, session.Meta["room"])
}

// baleDisconnectLiveKit is a no-op: there is never an active transport on js/wasm.
func (b *BaleCore) baleDisconnectLiveKit() {}
