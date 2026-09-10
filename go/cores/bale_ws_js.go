//go:build js

package cores

import (
	"context"

	"github.com/coder/websocket"
)

// baleWSDial connects to the Bale WebSocket endpoint from the browser.
// The js/wasm DialOptions only carries subprotocols: browsers forbid setting
// Cookie/User-Agent/Origin headers on a WebSocket handshake, so cookie-based
// auth cannot be attached here — the dial itself succeeds only if the page
// already carries the right cookies (same-origin web.bale.ai session).
func baleWSDial(ctx context.Context, url, _ string) (*websocket.Conn, error) {
	conn, _, err := websocket.Dial(ctx, url, nil)
	return conn, err
}
