//go:build js

package cores

import (
	"context"

	"github.com/coder/websocket"
)

// rubikaWSDial connects to the Rubika WebSocket endpoint from the browser.
// Browsers forbid custom headers on a WebSocket handshake; the dial works
// only same-origin (web.rubika.ir session cookies).
func rubikaWSDial(ctx context.Context, url, _ string) (*websocket.Conn, error) {
	conn, _, err := websocket.Dial(ctx, url, nil)
	return conn, err
}
